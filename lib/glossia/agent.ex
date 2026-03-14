defmodule Glossia.Agent do
  @moduledoc """
  A framework for building AI agents in Elixir.

  Glossia.Agent treats AI agents as first-class OTP processes that can
  reason, use tools, and orchestrate complex workflows.

  ## Defining an Agent

      defmodule MyApp.ResearchAgent do
        use Glossia.Agent

        @impl true
        def system_prompt do
          \"\"\"
          You are a research assistant that helps users find information.
          Be thorough and cite your sources.
          \"\"\"
        end

        @impl true
        def tools do
          [
            Glossia.Agent.Tools.Read,
            Glossia.Agent.Tools.Bash
          ]
        end
      end

  ## Running an Agent

      {:ok, agent} = MyApp.ResearchAgent.start_link(api_key: "sk-...")

      {:ok, response} = Glossia.Agent.run(agent, "What's new in Elixir 1.18?")

  ## Streaming Responses

      Glossia.Agent.stream(agent, "Explain OTP")
      |> Stream.each(fn
        {:text, chunk} -> IO.write(chunk)
        {:tool_call, name, _id, _args} -> IO.puts("\\nCalling: \#{name}")
        {:tool_result, _id, result} -> IO.puts("Result: \#{inspect(result)}")
        :done -> IO.puts("\\nDone!")
      end)
      |> Stream.run()

  ## Multi-Agent Workflows

  Agents can delegate to other agents:

      defmodule MyApp.Orchestrator do
        use Glossia.Agent

        @impl true
        def tools do
          [
            {Glossia.Agent.Tools.Delegate, agent: MyApp.ResearchAgent},
            {Glossia.Agent.Tools.Delegate, agent: MyApp.WriterAgent}
          ]
        end
      end

  ## Core Concepts

  - **Session** - A GenServer managing conversation state and the agent loop
  - **Message** - User, assistant, or tool result messages in the conversation
  - **Tool** - A capability the agent can invoke (read files, run commands, etc.)
  - **Provider** - An LLM backend (Anthropic, OpenAI, etc.)
  - **Event** - Notifications during agent execution for streaming/UI
  """

  @type thinking_level :: :off | :minimal | :low | :medium | :high

  @type event ::
          {:text, String.t()}
          | {:thinking, String.t()}
          | {:tool_call, name :: String.t(), id :: String.t(), args :: map()}
          | {:tool_result, id :: String.t(), result :: term()}
          | {:error, term()}
          | :agent_start
          | :agent_end
          | :turn_start
          | :turn_end
          | :message_start
          | :message_end
          | :done

  @type tool_spec :: module() | {module(), keyword()}

  # ============================================================================
  # Behaviour Definition
  # ============================================================================

  @doc """
  Returns the system prompt for this agent.
  """
  @callback system_prompt() :: String.t()

  @doc """
  Returns the list of tools this agent can use.
  """
  @callback tools() :: [tool_spec()]

  @doc """
  Returns the model identifier.
  """
  @callback model() :: String.t()

  @doc """
  Returns the provider module.
  """
  @callback provider() :: module()

  @doc """
  Returns the default thinking level.
  """
  @callback thinking_level() :: thinking_level()

  @doc """
  Initializes agent state from options.
  """
  @callback init(keyword()) :: {:ok, term()} | {:stop, term()}

  @doc """
  Handles events during execution.
  """
  @callback handle_event(event(), term()) :: {:noreply, term()} | {:stop, term(), term()}

  @optional_callbacks [tools: 0, model: 0, provider: 0, thinking_level: 0, init: 1, handle_event: 2]

  # ============================================================================
  # __using__ Macro
  # ============================================================================

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Glossia.Agent

      # Default implementations
      @impl Glossia.Agent
      def tools, do: []

      @impl Glossia.Agent
      def model, do: "claude-sonnet-4-20250514"

      @impl Glossia.Agent
      def provider, do: Glossia.Agent.Providers.Anthropic

      @impl Glossia.Agent
      def thinking_level, do: :medium

      @impl Glossia.Agent
      def init(opts), do: {:ok, opts}

      @impl Glossia.Agent
      def handle_event(_event, state), do: {:noreply, state}

      defoverridable tools: 0, model: 0, provider: 0, thinking_level: 0, init: 1, handle_event: 2

      @doc """
      Starts the agent process.

      ## Options

      - `:api_key` - API key for the LLM provider
      - `:provider` - Override the default provider
      - `:model` - Override the default model
      - `:thinking_level` - Override the thinking level
      - `:cwd` - Working directory for tools (default: File.cwd!())
      - `:name` - GenServer registration name

      Plus all standard GenServer options.
      """
      def start_link(opts \\ []) do
        Glossia.Agent.Session.start_link(__MODULE__, opts)
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent
        }
      end
    end
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs a prompt and returns the final response.

  ## Options

  - `:timeout` - Max time in ms (default: 300_000)
  - `:max_turns` - Max tool use cycles (default: 50)
  - `:images` - List of images to include (see Image module)

  ## Examples

      {:ok, response} = Glossia.Agent.run(agent, "Hello!")
  """
  @spec run(GenServer.server(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate run(agent, prompt, opts \\ []), to: Glossia.Agent.Session

  @doc """
  Streams a prompt, yielding events as they occur.

  ## Events

  - `{:text, chunk}` - Text chunk from LLM
  - `{:thinking, chunk}` - Thinking/reasoning chunk
  - `{:tool_call, name, id, args}` - Tool being called
  - `{:tool_result, id, result}` - Tool result
  - `{:error, reason}` - Error occurred
  - `:agent_start` - Agent started processing
  - `:agent_end` - Agent finished
  - `:turn_start` - New LLM turn starting
  - `:turn_end` - Turn completed
  - `:done` - Stream complete
  """
  @spec stream(GenServer.server(), String.t(), keyword()) :: Enumerable.t()
  defdelegate stream(agent, prompt, opts \\ []), to: Glossia.Agent.Session

  @doc """
  Returns the conversation history.
  """
  @spec history(GenServer.server()) :: [Glossia.Agent.Message.t()]
  defdelegate history(agent), to: Glossia.Agent.Session

  @doc """
  Clears conversation history.
  """
  @spec clear(GenServer.server()) :: :ok
  defdelegate clear(agent), to: Glossia.Agent.Session

  @doc """
  Aborts current operation.
  """
  @spec abort(GenServer.server()) :: :ok
  defdelegate abort(agent), to: Glossia.Agent.Session

  @doc """
  Injects a message mid-execution (steering).

  This message will be delivered after the current tool completes,
  and remaining tool calls will be skipped.
  """
  @spec steer(GenServer.server(), String.t()) :: :ok
  defdelegate steer(agent, message), to: Glossia.Agent.Session

  @doc """
  Queues a follow-up message.

  This message will be delivered when the agent finishes its current work.
  """
  @spec follow_up(GenServer.server(), String.t()) :: :ok
  defdelegate follow_up(agent, message), to: Glossia.Agent.Session
end
