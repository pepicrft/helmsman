# Agent

A framework for building AI agents in Elixir.

Agent treats AI agents as first-class OTP processes that can reason, use tools, and orchestrate complex workflows. Built on Erlang/OTP primitives for reliability and concurrency.

## Motivation

We built Agent at [Glossia](https://glossia.ai) to power our agentic workflows. We needed a framework that:

- Integrates naturally with OTP supervision trees
- Supports streaming for responsive user experiences
- Works with multiple LLM providers without vendor lock-in
- Provides extensible tooling for domain-specific capabilities

Rather than wrapping JavaScript agent frameworks, we built Agent from scratch using idiomatic Elixir patterns. We're sharing it with the community because we believe Elixir is an excellent fit for building reliable AI agents.

## Features

- **OTP-native**: Agents are GenServers that integrate naturally with supervision trees
- **Streaming**: Real-time event streaming for responsive UIs
- **Tool System**: Extensible tools for file operations, shell commands, and more
- **Multi-Provider**: 18+ LLM providers via [ReqLLM](https://github.com/agentjido/req_llm) (Anthropic, OpenAI, Google, etc.)
- **Telemetry**: Built-in observability with `:telemetry` events
- **Composable**: Agents can delegate to other agents for complex workflows

## Installation

Add `agent` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agent, github: "glossia/agent"}
  ]
end
```

## Quick Start

### 1. Define an Agent

```elixir
defmodule MyApp.CodingAgent do
  use Glossia.Agent

  @impl true
  def tools do
    Glossia.Agent.Tools.coding_tools()
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
{:ok, response} = Glossia.Agent.run(agent, "Create a GenServer that manages a counter")

# Stream responses for real-time output
Glossia.Agent.stream(agent, "Add documentation to the counter module")
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

## LiveBook

Agent works well in LiveBook notebooks with `Mix.install/1`:

```elixir
Mix.install([
  {:agent, github: "glossia/agent"}
])

Application.put_env(:agent, :api_key, System.fetch_env!("ANTHROPIC_API_KEY"))

defmodule NotebookAgent do
  use Glossia.Agent

  @impl true
  def tools do
    Glossia.Agent.Tools.read_only_tools()
  end
end

{:ok, agent} =
  NotebookAgent.start_link(
    system_prompt: "You are a helpful LiveBook assistant."
  )

{:ok, response} =
  Glossia.Agent.run(agent, "Summarize the current notebook context.")

response
```

For richer notebook output, you can stream events and render them with LiveBook/Kino cells as they arrive.

## Configuration

### API Keys

Set your API key via environment variable, application config, or option:

```elixir
# Environment variable (recommended) - ReqLLM auto-discovers these
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."

# Application config
config :agent,
  api_key: "sk-ant-...",
  system_prompt: "You are a helpful coding assistant."

# Per-agent option
MyApp.CodingAgent.start_link(api_key: "sk-ant-...")
```

Values passed to `start_link/1` take precedence over `config :agent`, which takes precedence over agent module defaults.

### Agent Options

```elixir
MyApp.CodingAgent.start_link(
  api_key: "sk-ant-...",                        # Overrides config :agent, :api_key
  model: "anthropic:claude-sonnet-4-20250514",  # Overrides config/module default
  system_prompt: "You are helpful.",            # Overrides config/module default
  thinking_level: :medium,                      # Overrides config/module default
  cwd: "/path/to/project",                      # Overrides config/default cwd
  name: MyApp.CodingAgent                       # GenServer name
)
```

### Supported Providers

Thanks to [ReqLLM](https://github.com/agentjido/req_llm), Agent supports 18+ providers:

| Provider | Model Format |
|----------|-------------|
| Anthropic | `anthropic:claude-sonnet-4-20250514` |
| OpenAI | `openai:gpt-4o` |
| Google Gemini | `google:gemini-2.0-flash` |
| Groq | `groq:llama-3.3-70b-versatile` |
| OpenRouter | `openrouter:anthropic/claude-3.5-sonnet` |
| xAI | `xai:grok-3` |
| And 12+ more... | See [ReqLLM docs](https://hexdocs.pm/req_llm) |

## Built-in Tools

### Default Tool Sets

```elixir
# Full coding tools: Read, Bash, Edit, Write
def tools, do: Glossia.Agent.Tools.coding_tools()

# Read-only: Read, Bash
def tools, do: Glossia.Agent.Tools.read_only_tools()
```

### Individual Tools

| Tool | Description |
|------|-------------|
| `Glossia.Agent.Tools.Read` | Read file contents, supports images |
| `Glossia.Agent.Tools.Bash` | Execute shell commands |
| `Glossia.Agent.Tools.Edit` | Surgical file edits (find & replace) |
| `Glossia.Agent.Tools.Write` | Create or overwrite files |

## Custom Tools

Define custom tools by implementing the `Glossia.Agent.Tool` behaviour:

```elixir
defmodule MyApp.Tools.Weather do
  use Glossia.Agent.Tool

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

## Events and Callbacks

Handle events during agent execution:

```elixir
defmodule MyApp.LoggingAgent do
  use Glossia.Agent

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

Agent emits telemetry events for observability:

```elixir
:telemetry.attach_many(
  "my-handler",
  [
    [:glossia, :agent, :start],
    [:glossia, :agent, :stop],
    [:glossia, :agent, :tool_call, :start],
    [:glossia, :agent, :tool_call, :stop]
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
Glossia.Agent.stream(agent, "Hello")
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

## Multi-Agent Workflows

Agents can delegate to other agents:

```elixir
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
```

## License

MIT License - see [LICENSE](LICENSE) for details.
