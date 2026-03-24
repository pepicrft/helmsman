defmodule Helmsman.Session do
  @moduledoc """
  GenServer that manages an agent session.

  The session maintains:
  - Conversation history (messages)
  - Current model configuration
  - Available tools
  - Streaming state

  ## The Agent Loop

  When a prompt is received:

  1. Add user message to history
  2. Call LLM with system prompt, messages, and tools
  3. If LLM returns tool calls:
     - Execute each tool
     - Add tool results to history
     - Go to step 2
  4. If LLM returns text only, return response
  """

  use GenServer

  alias Helmsman.{Message, SessionStore, Telemetry, Tool}
  alias Helmsman.SessionStore.Snapshot
  alias ReqLLM.ToolCall

  require Logger

  @default_timeout 300_000
  @default_max_turns 50

  defstruct [
    :agent_module,
    :model,
    :thinking_level,
    :system_prompt,
    :tools,
    :cwd,
    :api_key,
    :base_url,
    :session_store,
    :user_state,
    messages: [],
    streaming: false,
    abort_ref: nil,
    steering_messages: [],
    follow_up_messages: [],
    subscribers: []
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc false
  def start_link(agent_module, opts) do
    config = Keyword.get(opts, :config, [])
    explicit_keys = opts |> Keyword.keys() |> MapSet.new()
    opts = Keyword.delete(opts, :config)
    {gen_opts, agent_opts} = Keyword.split(opts, [:name])

    agent_opts =
      agent_opts
      |> Keyword.put_new(:agent_module, agent_module)
      |> Keyword.put(:explicit_keys, explicit_keys)
      |> put_configured_opt(config, :api_key)
      |> put_configured_opt(config, :base_url)
      |> put_configured_opt(config, :model, fn -> agent_module.model() end)
      |> put_configured_opt(config, :thinking_level, fn -> agent_module.thinking_level() end)
      |> put_configured_opt(config, :system_prompt, fn -> agent_module.system_prompt() end)
      |> Keyword.put_new(:tools, agent_module.tools())
      |> put_configured_opt(config, :cwd, &File.cwd!/0)
      |> put_configured_opt(config, :session_store)

    GenServer.start_link(__MODULE__, agent_opts, gen_opts)
  end

  defp put_configured_opt(opts, config, key, default_fun \\ fn -> nil end) do
    Keyword.put_new_lazy(opts, key, fn ->
      Keyword.get_lazy(config, key, fn ->
        Application.get_env(:helmsman, key, default_fun.())
      end)
    end)
  end

  @doc """
  Runs a prompt synchronously, returning the final response.
  """
  def run(agent, prompt, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(agent, {:run, prompt, opts}, timeout)
  end

  @doc """
  Streams a prompt, returning an enumerable of events.
  """
  def stream(agent, prompt, opts \\ []) do
    Stream.resource(
      fn ->
        ref = make_ref()
        :ok = GenServer.call(agent, {:subscribe, self(), ref})
        :ok = GenServer.cast(agent, {:stream, prompt, opts, ref})
        ref
      end,
      fn ref ->
        receive do
          {^ref, :done} ->
            {:halt, ref}

          {^ref, event} ->
            {[event], ref}
        after
          @default_timeout ->
            {[{:error, :timeout}], ref}
        end
      end,
      fn ref ->
        GenServer.cast(agent, {:unsubscribe, self(), ref})
      end
    )
  end

  @doc """
  Returns the conversation history.
  """
  def history(agent) do
    GenServer.call(agent, :history)
  end

  @doc """
  Clears the conversation history.
  """
  def clear(agent) do
    GenServer.call(agent, :clear)
  end

  @doc """
  Aborts the current operation.
  """
  def abort(agent) do
    GenServer.call(agent, :abort)
  end

  @doc """
  Injects a steering message.
  """
  def steer(agent, message) do
    GenServer.call(agent, {:steer, message})
  end

  @doc """
  Queues a follow-up message.
  """
  def follow_up(agent, message) do
    GenServer.call(agent, {:follow_up, message})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    agent_module = Keyword.fetch!(opts, :agent_module)
    session_store = Keyword.get(opts, :session_store)
    snapshot = load_snapshot(session_store, opts)

    case agent_module.init(opts) do
      {:ok, user_state} ->
        state =
          %__MODULE__{
            agent_module: agent_module,
            model: restore_value(opts, :model, snapshot && snapshot.model),
            thinking_level: restore_value(opts, :thinking_level, snapshot && snapshot.thinking_level),
            system_prompt: restore_value(opts, :system_prompt, snapshot && snapshot.system_prompt),
            tools: Keyword.fetch!(opts, :tools),
            cwd: Keyword.fetch!(opts, :cwd),
            api_key: opts[:api_key],
            base_url: opts[:base_url],
            session_store: session_store,
            user_state: user_state
          }
          |> restore_messages(snapshot)

        {:ok, state}

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:run, prompt, opts}, from, state) do
    if state.streaming do
      {:reply, {:error, :already_streaming}, state}
    else
      state = %{state | streaming: true, abort_ref: make_ref()}
      parent = self()

      Task.start(fn ->
        result = do_run(state, prompt, opts)
        GenServer.cast(parent, {:run_complete, from, result})
      end)

      {:noreply, state}
    end
  end

  def handle_call({:subscribe, pid, ref}, _from, state) do
    {:reply, :ok, %{state | subscribers: [{pid, ref} | state.subscribers]}}
  end

  def handle_call(:history, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:clear, _from, state) do
    state = %{state | messages: []}
    persist_or_clear_snapshot(state, :clear)
    {:reply, :ok, state}
  end

  def handle_call(:abort, _from, state) do
    {:reply, :ok, %{state | abort_ref: make_ref(), streaming: false}}
  end

  def handle_call({:steer, message}, _from, state) do
    msg = Message.user(message)
    {:reply, :ok, %{state | steering_messages: state.steering_messages ++ [msg]}}
  end

  def handle_call({:follow_up, message}, _from, state) do
    msg = Message.user(message)
    {:reply, :ok, %{state | follow_up_messages: state.follow_up_messages ++ [msg]}}
  end

  @impl true
  def handle_cast({:stream, prompt, opts, subscriber_ref}, state) do
    if state.streaming do
      broadcast(state, subscriber_ref, {:error, :already_streaming})
      broadcast(state, subscriber_ref, :done)
      {:noreply, state}
    else
      state = %{state | streaming: true, abort_ref: make_ref()}
      parent = self()
      abort_ref = state.abort_ref

      Task.start(fn ->
        result =
          do_stream(
            state,
            prompt,
            opts,
            fn event ->
              GenServer.cast(parent, {:broadcast_event, event, subscriber_ref})
            end,
            abort_ref
          )

        GenServer.cast(parent, {:stream_complete, subscriber_ref, result})
      end)

      {:noreply, state}
    end
  end

  def handle_cast({:unsubscribe, pid, ref}, state) do
    subscribers = Enum.reject(state.subscribers, fn {p, r} -> p == pid and r == ref end)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_cast({:broadcast_event, event, ref}, state) do
    broadcast(state, ref, event)
    {:noreply, maybe_dispatch_event(state, event)}
  end

  def handle_cast({:run_complete, from, {result, messages}}, state) do
    GenServer.reply(from, result)
    state = %{state | streaming: false, messages: messages}
    persist_snapshot(state)
    {:noreply, state}
  end

  def handle_cast({:stream_complete, ref, {:ok, messages, _response}}, state) do
    broadcast(state, ref, :done)
    state = %{state | streaming: false, messages: messages}
    persist_snapshot(state)
    {:noreply, state}
  end

  def handle_cast({:stream_complete, ref, _result}, state) do
    broadcast(state, ref, :done)
    {:noreply, %{state | streaming: false}}
  end

  # ============================================================================
  # Agent Loop Implementation
  # ============================================================================

  defp do_run(state, prompt, opts) do
    max_turns = opts[:max_turns] || @default_max_turns
    images = opts[:images] || []

    user_message = Message.user(prompt, images)
    messages = state.messages ++ [user_message]

    Telemetry.span(:agent, %{agent: state.agent_module}, fn ->
      case agent_loop(state, messages, max_turns, 0) do
        {:ok, final_messages, response} ->
          {{:ok, response}, final_messages}

        {:error, reason} ->
          {{:error, reason}, messages}
      end
    end)
  end

  defp do_stream(state, prompt, opts, emit, abort_ref) do
    max_turns = opts[:max_turns] || @default_max_turns
    images = opts[:images] || []

    user_message = Message.user(prompt, images)
    messages = state.messages ++ [user_message]

    emit.(:agent_start)

    Telemetry.span(:agent, %{agent: state.agent_module}, fn ->
      result = streaming_loop(state, messages, max_turns, 0, emit, abort_ref)
      emit.(:agent_end)
      result
    end)
  end

  defp agent_loop(_state, messages, max_turns, turn) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response}
  end

  defp agent_loop(state, messages, max_turns, turn) do
    context = build_context(state, messages)
    tools = build_req_llm_tools(state.tools, state)
    llm_opts = build_llm_opts(state, tools)

    case ReqLLM.generate_text(state.model, context, llm_opts) do
      {:ok, response} ->
        assistant_message = response_to_message(response)
        messages = messages ++ [assistant_message]

        if Message.has_tool_calls?(assistant_message) do
          {tool_results, messages} = execute_tool_calls(state, assistant_message, messages)
          messages = messages ++ tool_results
          agent_loop(state, messages, max_turns, turn + 1)
        else
          response_text = Message.text(assistant_message)
          {:ok, messages, response_text}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp streaming_loop(_state, messages, max_turns, turn, _emit, _abort_ref) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response}
  end

  defp streaming_loop(state, messages, max_turns, turn, emit, abort_ref) do
    if state.abort_ref == abort_ref do
      emit.(:turn_start)

      context = build_context(state, messages)
      tools = build_req_llm_tools(state.tools, state)
      llm_opts = build_llm_opts(state, tools)

      case ReqLLM.stream_text(state.model, context, llm_opts) do
        {:ok, stream_response} ->
          case ReqLLM.StreamResponse.process_stream(
                 stream_response,
                 on_result: fn chunk -> emit.({:text, chunk}) end,
                 on_thinking: fn chunk -> emit.({:thinking, chunk}) end
               ) do
            {:ok, response} ->
              assistant_message = response_to_message(response)
              text = ReqLLM.Response.text(response) || ""
              emit.(:turn_end)

              if Message.has_tool_calls?(assistant_message) do
                messages = messages ++ [assistant_message]
                {tool_results, messages} = execute_tool_calls_streaming(state, assistant_message, messages, emit)
                messages = messages ++ tool_results
                streaming_loop(state, messages, max_turns, turn + 1, emit, abort_ref)
              else
                messages = messages ++ [assistant_message]
                {:ok, messages, text}
              end

            {:error, reason} ->
              emit.({:error, reason})
              {:error, reason}
          end

        {:error, reason} ->
          emit.({:error, reason})
          {:error, reason}
      end
    else
      {:error, :aborted}
    end
  end

  defp build_context(state, messages) do
    context_messages =
      messages
      |> Enum.map(&message_to_req_llm/1)
      |> List.flatten()

    if state.system_prompt do
      ReqLLM.Context.new([
        ReqLLM.Context.system(state.system_prompt) | context_messages
      ])
    else
      ReqLLM.Context.new(context_messages)
    end
  end

  defp message_to_req_llm(%Message{role: :user, content: content, images: []}) do
    ReqLLM.Context.user(content)
  end

  defp message_to_req_llm(%Message{role: :user, content: content, images: images}) when images != [] do
    # Include images as content parts
    image_parts =
      Enum.map(images, fn img ->
        {:image, "data:#{img.media_type};base64,#{img.data}"}
      end)

    ReqLLM.Context.user([{:text, content} | image_parts])
  end

  defp message_to_req_llm(%Message{role: :assistant, content: content}) when is_binary(content) do
    ReqLLM.Context.assistant(content)
  end

  defp message_to_req_llm(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    text =
      blocks
      |> Enum.filter(&match?({:text, _}, &1))
      |> Enum.map_join("", fn {:text, t} -> t end)

    tool_calls =
      blocks
      |> Enum.filter(&match?({:tool_call, _, _, _}, &1))
      |> Enum.map(fn {:tool_call, id, name, arguments} ->
        %{id: id, name: name, arguments: arguments}
      end)

    if tool_calls == [] do
      ReqLLM.Context.assistant(text)
    else
      ReqLLM.Context.assistant(text, tool_calls: tool_calls)
    end
  end

  defp message_to_req_llm(%Message{role: :tool_result, tool_call_id: id, content: content}) do
    result = if is_binary(content), do: content, else: JSON.encode!(content)
    ReqLLM.Context.tool_result(id, result)
  end

  defp build_req_llm_tools(tools, state) do
    Enum.map(tools, fn tool_spec ->
      spec = Tool.to_spec(tool_spec)

      ReqLLM.tool(
        name: spec.name,
        description: spec.description,
        parameter_schema: convert_json_schema_to_nimble(spec.parameters),
        callback: fn args ->
          context = %{agent: self(), cwd: state.cwd, opts: []}

          case Tool.execute(tool_spec, args, context) do
            {:ok, result} when is_binary(result) -> result
            {:ok, result} -> JSON.encode!(result)
            {:error, reason} -> "Error: #{inspect(reason)}"
          end
        end
      )
    end)
  end

  defp convert_json_schema_to_nimble(%{properties: props, required: required}) do
    props
    |> Enum.map(fn {name, schema} ->
      name_atom = if is_binary(name), do: String.to_atom(name), else: name

      opts = [
        type: json_type_to_nimble(schema[:type] || schema["type"]),
        required: name in (required || []) or to_string(name) in (required || []),
        doc: schema[:description] || schema["description"] || ""
      ]

      {name_atom, opts}
    end)
  end

  defp convert_json_schema_to_nimble(%{"properties" => props} = schema) do
    required = schema["required"] || []
    convert_json_schema_to_nimble(%{properties: props, required: required})
  end

  defp convert_json_schema_to_nimble(_), do: []

  defp json_type_to_nimble("string"), do: :string
  defp json_type_to_nimble("number"), do: :float
  defp json_type_to_nimble("integer"), do: :integer
  defp json_type_to_nimble("boolean"), do: :boolean
  defp json_type_to_nimble("array"), do: {:list, :any}
  defp json_type_to_nimble("object"), do: :map
  defp json_type_to_nimble(_), do: :string

  defp build_llm_opts(state, tools) do
    opts = []

    opts = if state.api_key, do: Keyword.put(opts, :api_key, state.api_key), else: opts
    opts = if state.base_url, do: Keyword.put(opts, :base_url, state.base_url), else: opts
    opts = if tools == [], do: opts, else: Keyword.put(opts, :tools, tools)

    # Add thinking level for supported providers
    opts =
      case state.thinking_level do
        :off ->
          Keyword.put(opts, :reasoning_effort, :none)

        level when level in [:minimal, :low, :medium, :high] ->
          Keyword.put(opts, :reasoning_effort, level)

        _ ->
          opts
      end

    opts
  end

  defp response_to_message(response) do
    thinking_blocks =
      case ReqLLM.Response.thinking(response) do
        nil -> []
        "" -> []
        thinking -> [{:thinking, thinking}]
      end

    text_blocks =
      case ReqLLM.Response.text(response) do
        nil -> []
        "" -> []
        text -> [{:text, text}]
      end

    tool_calls =
      response
      |> ReqLLM.Response.tool_calls()
      |> Enum.map(fn call ->
        normalized = ToolCall.from_map(call)
        {:tool_call, normalized.id, normalized.name, normalized.arguments}
      end)

    blocks = thinking_blocks ++ text_blocks ++ tool_calls

    if blocks == [] do
      Message.assistant("")
    else
      Message.assistant(blocks)
    end
  end

  defp execute_tool_calls(state, assistant_message, messages) do
    tool_calls = Message.tool_calls(assistant_message)
    tool_map = build_tool_map(state.tools)

    tool_results =
      Enum.map(tool_calls, fn {id, name, args} ->
        Telemetry.span(:tool_call, %{tool: name}, fn ->
          execute_tool(tool_map, name, args, state, id)
        end)
      end)

    {tool_results, messages}
  end

  defp execute_tool_calls_streaming(state, assistant_message, messages, emit) do
    tool_calls = Message.tool_calls(assistant_message)
    tool_map = build_tool_map(state.tools)

    tool_results =
      Enum.map(tool_calls, fn {id, name, args} ->
        emit.({:tool_call, name, id, args})

        result =
          Telemetry.span(:tool_call, %{tool: name}, fn ->
            execute_tool(tool_map, name, args, state, id)
          end)

        emit.({:tool_result, id, Message.tool_result_content(result)})
        result
      end)

    {tool_results, messages}
  end

  defp execute_tool(tool_map, name, args, state, id) do
    case Map.get(tool_map, name) do
      nil ->
        Message.tool_result(id, {:error, "Unknown tool: #{name}"})

      {module, opts} ->
        context = %{agent: self(), cwd: state.cwd, opts: opts}

        case Tool.execute({module, opts}, args, context) do
          {:ok, result} -> Message.tool_result(id, result)
          {:error, reason} -> Message.tool_result(id, {:error, reason})
        end

      module ->
        context = %{agent: self(), cwd: state.cwd, opts: []}

        case Tool.execute(module, args, context) do
          {:ok, result} -> Message.tool_result(id, result)
          {:error, reason} -> Message.tool_result(id, {:error, reason})
        end
    end
  end

  defp build_tool_map(tools) do
    tools
    |> Map.new(fn
      {module, opts} = spec -> {Tool.name(spec), {module, opts}}
      module -> {Tool.name(module), module}
    end)
  end

  defp extract_text_response(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :assistant))
    |> case do
      nil -> ""
      msg -> Message.text(msg)
    end
  end

  defp broadcast(state, ref, event) do
    for {pid, ^ref} <- state.subscribers do
      send(pid, {ref, event})
    end
  end

  defp maybe_dispatch_event(state, event) do
    case state.agent_module.handle_event(event, state.user_state) do
      {:noreply, user_state} ->
        %{state | user_state: user_state}

      {:stop, _reason, user_state} ->
        %{state | user_state: user_state, streaming: false}
    end
  end

  defp restore_value(opts, key, stored_value) do
    explicit_keys = Keyword.get(opts, :explicit_keys, MapSet.new())

    cond do
      MapSet.member?(explicit_keys, key) ->
        Keyword.fetch!(opts, key)

      is_nil(stored_value) ->
        Keyword.get(opts, key)

      true ->
        stored_value
    end
  end

  defp restore_messages(state, nil), do: state
  defp restore_messages(state, %Snapshot{messages: messages}), do: %{state | messages: messages}

  defp load_snapshot(nil, _opts), do: nil

  defp load_snapshot(session_store, opts) do
    case SessionStore.load(session_store, session_store_opts(opts)) do
      {:ok, %Snapshot{} = snapshot} ->
        snapshot

      :not_found ->
        nil

      {:error, reason} ->
        Logger.warning("failed to load session snapshot: #{inspect(reason)}")
        nil
    end
  end

  defp persist_or_clear_snapshot(%__MODULE__{session_store: nil}, _mode), do: :ok

  defp persist_or_clear_snapshot(state, :clear) do
    case SessionStore.clear(state.session_store, session_store_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to clear session snapshot: #{inspect(reason)}")
        :ok
    end
  end

  defp persist_snapshot(%__MODULE__{session_store: nil}), do: :ok

  defp persist_snapshot(state) do
    snapshot = %Snapshot{
      messages: state.messages,
      model: state.model,
      thinking_level: state.thinking_level,
      system_prompt: state.system_prompt
    }

    case SessionStore.save(state.session_store, snapshot, session_store_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to persist session snapshot: #{inspect(reason)}")
        :ok
    end
  end

  defp session_store_opts(opts) when is_list(opts) do
    [
      agent_module: Keyword.get(opts, :agent_module),
      cwd: Keyword.get(opts, :cwd)
    ]
  end

  defp session_store_opts(%__MODULE__{} = state) do
    [
      agent_module: state.agent_module,
      cwd: state.cwd
    ]
  end
end
