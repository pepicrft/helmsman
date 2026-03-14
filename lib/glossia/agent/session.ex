defmodule Glossia.Agent.Session do
  @moduledoc """
  GenServer that manages an agent session.

  The session maintains:
  - Conversation history (messages)
  - Current model and provider
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

  alias Glossia.Agent.{Message, Tool, Telemetry}

  require Logger

  @default_timeout 300_000
  @default_max_turns 50

  defstruct [
    :agent_module,
    :provider,
    :model,
    :thinking_level,
    :system_prompt,
    :tools,
    :cwd,
    :api_key,
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
    {gen_opts, agent_opts} = Keyword.split(opts, [:name])

    agent_opts =
      agent_opts
      |> Keyword.put_new(:agent_module, agent_module)
      |> Keyword.put_new(:provider, agent_module.provider())
      |> Keyword.put_new(:model, agent_module.model())
      |> Keyword.put_new(:thinking_level, agent_module.thinking_level())
      |> Keyword.put_new(:system_prompt, agent_module.system_prompt())
      |> Keyword.put_new(:tools, agent_module.tools())
      |> Keyword.put_new(:cwd, File.cwd!())

    GenServer.start_link(__MODULE__, agent_opts, gen_opts)
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

    case agent_module.init(opts) do
      {:ok, user_state} ->
        state = %__MODULE__{
          agent_module: agent_module,
          provider: Keyword.fetch!(opts, :provider),
          model: Keyword.fetch!(opts, :model),
          thinking_level: Keyword.fetch!(opts, :thinking_level),
          system_prompt: Keyword.fetch!(opts, :system_prompt),
          tools: Keyword.fetch!(opts, :tools),
          cwd: Keyword.fetch!(opts, :cwd),
          api_key: opts[:api_key],
          user_state: user_state
        }

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
      # Run in a separate process to avoid blocking
      state = %{state | streaming: true, abort_ref: make_ref()}

      Task.start(fn ->
        result = do_run(state, prompt, opts)
        GenServer.cast(self(), {:run_complete, from, result})
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
    {:reply, :ok, %{state | messages: []}}
  end

  def handle_call(:abort, _from, state) do
    # Signal abort by updating the ref
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
        do_stream(
          state,
          prompt,
          opts,
          fn event ->
            GenServer.cast(parent, {:broadcast_event, event, subscriber_ref})
          end,
          abort_ref
        )

        GenServer.cast(parent, {:stream_complete, subscriber_ref})
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
    {:noreply, %{state | streaming: false, messages: messages}}
  end

  def handle_cast({:stream_complete, ref}, state) do
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
      case agent_loop(state, messages, max_turns, 0, nil) do
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

  defp agent_loop(_state, messages, max_turns, turn, _last_response) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response}
  end

  defp agent_loop(state, messages, max_turns, turn, _last_response) do
    tool_specs = build_tool_specs(state.tools)

    provider_opts = [
      api_key: state.api_key,
      model: state.model,
      thinking_level: state.thinking_level,
      system: state.system_prompt
    ]

    case state.provider.chat(messages, tool_specs, provider_opts) do
      {:ok, assistant_message} ->
        messages = messages ++ [assistant_message]

        if Message.has_tool_calls?(assistant_message) do
          # Execute tools and continue loop
          {tool_results, messages} = execute_tool_calls(state, assistant_message, messages)
          messages = messages ++ tool_results
          agent_loop(state, messages, max_turns, turn + 1, nil)
        else
          # No tool calls, we're done
          response = Message.text(assistant_message)
          {:ok, messages, response}
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
    # Check for abort
    if state.abort_ref != abort_ref do
      {:error, :aborted}
    else
      emit.(:turn_start)

      tool_specs = build_tool_specs(state.tools)

      provider_opts = [
        api_key: state.api_key,
        model: state.model,
        thinking_level: state.thinking_level,
        system: state.system_prompt
      ]

      # Stream the response, collecting events
      assistant_message =
        state.provider.stream(messages, tool_specs, provider_opts)
        |> Enum.reduce(nil, fn event, _acc ->
          emit.(event)

          case event do
            {:message_complete, msg} -> msg
            _ -> nil
          end
        end)

      emit.(:turn_end)

      if assistant_message && Message.has_tool_calls?(assistant_message) do
        messages = messages ++ [assistant_message]

        # Check for steering messages
        case check_steering(state) do
          [] ->
            # Execute tools
            {tool_results, messages} = execute_tool_calls_streaming(state, assistant_message, messages, emit)
            messages = messages ++ tool_results
            streaming_loop(state, messages, max_turns, turn + 1, emit, abort_ref)

          steering ->
            # Skip remaining tools, inject steering
            messages = messages ++ steering
            streaming_loop(state, messages, max_turns, turn + 1, emit, abort_ref)
        end
      else
        messages = if assistant_message, do: messages ++ [assistant_message], else: messages

        # Check for follow-up messages
        case check_follow_up(state) do
          [] ->
            response = extract_text_response(messages)
            {:ok, messages, response}

          follow_ups ->
            messages = messages ++ follow_ups
            streaming_loop(state, messages, max_turns, turn + 1, emit, abort_ref)
        end
      end
    end
  end

  defp check_steering(_state) do
    # TODO: Get steering messages from state atomically
    []
  end

  defp check_follow_up(_state) do
    # TODO: Get follow-up messages from state atomically
    []
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
        context = %{
          agent: self(),
          cwd: state.cwd,
          opts: opts
        }

        case Tool.execute({module, opts}, args, context) do
          {:ok, result} ->
            Message.tool_result(id, result)

          {:error, reason} ->
            Message.tool_result(id, {:error, reason})
        end

      module ->
        context = %{
          agent: self(),
          cwd: state.cwd,
          opts: []
        }

        case Tool.execute(module, args, context) do
          {:ok, result} ->
            Message.tool_result(id, result)

          {:error, reason} ->
            Message.tool_result(id, {:error, reason})
        end
    end
  end

  defp build_tool_specs(tools) do
    Enum.map(tools, &Tool.to_spec/1)
  end

  defp build_tool_map(tools) do
    tools
    |> Enum.map(fn
      {module, opts} = spec -> {Tool.name(spec), {module, opts}}
      module -> {Tool.name(module), module}
    end)
    |> Map.new()
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
end
