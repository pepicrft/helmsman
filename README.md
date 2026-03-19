# Helmsman ⚓

[![Hex.pm](https://img.shields.io/hexpm/v/helmsman.svg)](https://hex.pm/packages/helmsman)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/helmsman/)
[![CI](https://github.com/pepicrft/helmsman/actions/workflows/helmsman.yml/badge.svg)](https://github.com/pepicrft/helmsman/actions/workflows/helmsman.yml)

A framework for building AI agents in Elixir.

Install it from [Hex.pm](https://hex.pm/packages/helmsman) and browse the guides on [HexDocs](https://hexdocs.pm/helmsman/).

Helmsman treats AI agents as first-class OTP processes that can reason, use tools, and orchestrate complex workflows. Built on Erlang/OTP primitives for reliability and concurrency.

## Motivation 💡

Helmsman grew out of practical work building agentic workflows. We needed a framework that:

- Integrates naturally with OTP supervision trees
- Supports streaming for responsive user experiences
- Works with multiple LLM providers without vendor lock-in
- Provides extensible tooling for domain-specific capabilities

Rather than wrapping JavaScript agent frameworks, we built Helmsman from scratch using idiomatic Elixir patterns. We are sharing it because Elixir is an excellent fit for building reliable AI agents.

## Features ✨

- **OTP-native**: Agents are GenServers that integrate naturally with supervision trees
- **Streaming**: Real-time event streaming for responsive UIs
- **Tool System**: Extensible tools for file operations, shell commands, and more
- **Multi-Provider**: 18+ LLM providers via [ReqLLM](https://github.com/agentjido/req_llm) (Anthropic, OpenAI, Google, etc.)
- **Telemetry**: Built-in observability with `:telemetry` events

## Installation 📦

Add `helmsman` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:helmsman, "~> 0.1.0"}
  ]
end
```

## Quick Start 🚀

### 1. Define an Agent

```elixir
defmodule MyApp.CodingAgent do
  use Helmsman

  @impl true
  def tools do
    Helmsman.Tools.coding_tools()
  end
end
```

### 2. Start and Use the Agent

```elixir
# Start the agent with an explicit system prompt override
{:ok, agent} = MyApp.CodingAgent.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  system_prompt: """
  You are an expert software engineer.
  Write clean, well-documented code.
  Always run tests after making changes.
  """
)

# Run a prompt
{:ok, response} = Helmsman.run(agent, "Create a GenServer that manages a counter")

# Stream responses for real-time output
Helmsman.stream(agent, "Add documentation to the counter module")
|> Stream.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:tool_call, name, _id, _args} -> IO.puts("\n📦 Using tool: #{name}")
  {:tool_result, _id, result} -> IO.puts("   Result: #{inspect(result)}")
  :done -> IO.puts("\n✅ Done!")
  _ -> :ok
end)
|> Stream.run()
```

### 3. Add to Supervision Tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.CodingAgent,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        system_prompt: "You are a helpful coding assistant."}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## LiveBook 📓

Helmsman works well in LiveBook notebooks with `Mix.install/1`:

```elixir
Mix.install([
  {:helmsman, "~> 0.1.0"}
])

Application.put_env(:helmsman, :api_key, System.fetch_env!("ANTHROPIC_API_KEY"))

defmodule NotebookAgent do
  use Helmsman

  @impl true
  def tools do
    Helmsman.Tools.read_only_tools()
  end
end

{:ok, agent} =
  NotebookAgent.start_link(
    system_prompt: "You are a helpful LiveBook assistant."
  )

{:ok, response} =
  Helmsman.run(agent, "Summarize the current notebook context.")

response
```

For richer notebook output, you can stream events and render them with LiveBook/Kino cells as they arrive.

## Configuration ⚙️

### API Keys

Set your API key via environment variable, application config, or option:

```elixir
# Environment variable (recommended) - ReqLLM auto-discovers these
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."

# Application config
config :helmsman,
  api_key: "sk-ant-...",
  system_prompt: "You are a helpful coding assistant."

# Per-agent option
MyApp.CodingAgent.start_link(api_key: "sk-ant-...")
```

Values passed to `start_link/1` take precedence over `config :helmsman`, which takes precedence over agent module defaults.

### Agent Options

```elixir
MyApp.CodingAgent.start_link(
  api_key: "sk-ant-...",                        # Overrides config :helmsman, :api_key
  model: "anthropic:claude-sonnet-4-20250514",  # Overrides config/module default
  system_prompt: "You are helpful.",            # Overrides config/module default
  thinking_level: :medium,                      # Overrides config/module default
  cwd: "/path/to/project",                      # Overrides config/default cwd
  session_store: Helmsman.SessionStore.Memory,  # Optional session persistence
  name: MyApp.CodingAgent                       # GenServer name
)
```

### Session Storage

Persisted sessions are opt-in. Provide a session store to save and restore
conversation history plus session settings.

Built-in session stores:

- `Helmsman.SessionStore.Memory` stores snapshots in ETS for reuse within the current VM
- `Helmsman.SessionStore.Disk` persists snapshots to disk across restarts

```elixir
# Restore within the current VM
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Helmsman.SessionStore.Memory, key: {:coding_agent, "/tmp/project"}}
  )

# Persist to disk across restarts
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/tmp/project",
    session_store: Helmsman.SessionStore.Disk
  )

# Custom path or custom implementation
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Helmsman.SessionStore.Disk, path: "/tmp/helmsman.session"}
  )
```

### Supported Providers

Thanks to [ReqLLM](https://github.com/agentjido/req_llm), Helmsman supports 18+ providers:

| Provider | Model Format |
|----------|-------------|
| Anthropic | `anthropic:claude-sonnet-4-20250514` |
| OpenAI | `openai:gpt-4o` |
| Google Gemini | `google:gemini-2.0-flash` |
| Groq | `groq:llama-3.3-70b-versatile` |
| OpenRouter | `openrouter:anthropic/claude-3.5-sonnet` |
| xAI | `xai:grok-3` |
| And 12+ more... | See [ReqLLM docs](https://hexdocs.pm/req_llm) |

## Built-in Tools 🧰

### Default Tool Sets

```elixir
# Full coding tools: Read, Bash, Edit, Write
def tools, do: Helmsman.Tools.coding_tools()

# Read-only: Read, Bash
def tools, do: Helmsman.Tools.read_only_tools()
```

### Individual Tools

| Tool | Description |
|------|-------------|
| `Helmsman.Tools.Read` | Read file contents, supports images |
| `Helmsman.Tools.Bash` | Execute shell commands |
| `Helmsman.Tools.Edit` | Surgical file edits (find & replace) |
| `Helmsman.Tools.Write` | Create or overwrite files |

## Custom Tools 🛠️

Define custom tools by implementing the `Helmsman.Tool` behaviour:

```elixir
defmodule MyApp.Tools.Weather do
  use Helmsman.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Gets the current weather for a location"

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City name"}
      },
      required: ["location"]
    }
  end

  @impl true
  def call(%{"location" => location}, _context) do
    case WeatherAPI.get(location) do
      {:ok, data} -> {:ok, "Temperature: #{data.temp}°F"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Events and Callbacks 📡

Handle events during agent execution:

```elixir
defmodule MyApp.LoggingAgent do
  use Helmsman

  @impl true
  def handle_event({:tool_call, name, _id, _args}, state) do
    Logger.info("Agent calling tool: #{name}")
    {:noreply, state}
  end

  @impl true
  def handle_event({:text, chunk}, state) do
    # Stream to WebSocket, etc.
    {:noreply, state}
  end

  @impl true
  def handle_event(_event, state), do: {:noreply, state}
end
```

## Telemetry

Helmsman emits telemetry events for observability:

```elixir
:telemetry.attach_many(
  "my-handler",
  [
    [:helmsman, :agent, :start],
    [:helmsman, :agent, :stop],
    [:helmsman, :tool_call, :start],
    [:helmsman, :tool_call, :stop]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("#{inspect(event)}: #{inspect(measurements)}")
  end,
  nil
)
```

## Streaming API

The streaming API returns an enumerable of events:

```elixir
Helmsman.stream(agent, "Hello")
|> Enum.each(fn event ->
  case event do
    {:text, chunk} -> IO.write(chunk)
    {:thinking, chunk} -> IO.write(IO.ANSI.faint() <> chunk <> IO.ANSI.reset())
    {:tool_call, name, id, args} -> IO.inspect({name, args})
    {:tool_result, id, result} -> IO.inspect(result)
    {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
    :agent_start -> IO.puts("Agent started")
    :agent_end -> IO.puts("Agent finished")
    :turn_start -> nil
    :turn_end -> nil
    :done -> IO.puts("\nDone")
  end
end)
```

## License

MIT License - see [LICENSE](LICENSE) for details.
