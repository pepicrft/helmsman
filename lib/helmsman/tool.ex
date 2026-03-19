defmodule Helmsman.Tool do
  @moduledoc """
  Behaviour for defining tools that agents can use.

  Tools are functions that agents can call to interact with the world:
  reading files, running commands, making HTTP requests, etc.

  ## Defining a Tool

      defmodule MyApp.Tools.Weather do
        use Helmsman.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description do
          "Gets the current weather for a location"
        end

        @impl true
        def parameters do
          %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "City name, e.g. 'San Francisco, CA'"
              }
            },
            required: ["location"]
          }
        end

        @impl true
        def call(%{"location" => location}, _context) do
          case WeatherAPI.get(location) do
            {:ok, data} -> {:ok, format_weather(data)}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  ## Tool Context

  The `call/2` function receives a context map with:

  - `:agent` - The agent PID
  - `:cwd` - Current working directory
  - `:opts` - Options passed when adding the tool to the agent

  ## Parameterized Tools

  Tools can be parameterized when added to an agent:

      defmodule MyApp.Tools.Database do
        use Helmsman.Tool

        @impl true
        def name(opts), do: "query_\#{opts[:table]}"

        @impl true
        def description(opts) do
          "Query the \#{opts[:table]} table"
        end

        @impl true
        def call(args, context) do
          table = context.opts[:table]
          Repo.all(from r in table, where: ^build_where(args))
        end
      end

      # In agent:
      def tools do
        [
          {MyApp.Tools.Database, table: "users"},
          {MyApp.Tools.Database, table: "orders"}
        ]
      end
  """

  @type context :: %{
          agent: pid(),
          cwd: String.t(),
          opts: keyword()
        }

  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Returns the tool name as it will appear to the LLM.
  """
  @callback name() :: String.t()
  @callback name(opts :: keyword()) :: String.t()

  @doc """
  Returns a description of what the tool does.
  """
  @callback description() :: String.t()
  @callback description(opts :: keyword()) :: String.t()

  @doc """
  Returns the JSON Schema for the tool's parameters.
  """
  @callback parameters() :: map()
  @callback parameters(opts :: keyword()) :: map()

  @doc """
  Executes the tool with the given arguments.
  """
  @callback call(args :: map(), context()) :: result()

  @optional_callbacks [name: 1, description: 1, parameters: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Helmsman.Tool

      # Default: no-opts versions delegate to opts versions with empty list
      def name, do: name([])
      def description, do: description([])
      def parameters, do: parameters([])

      # Default opts implementations call the no-opts versions
      def name([]), do: raise("#{inspect(__MODULE__)} must implement name/0 or name/1")

      def description([]), do: raise("#{inspect(__MODULE__)} must implement description/0 or description/1")

      def parameters([]), do: raise("#{inspect(__MODULE__)} must implement parameters/0 or parameters/1")

      defoverridable name: 0, name: 1, description: 0, description: 1, parameters: 0, parameters: 1
    end
  end

  @doc """
  Gets the tool name for a tool spec.
  """
  @spec name(module() | {module(), keyword()}) :: String.t()
  def name({module, opts}), do: module.name(opts)
  def name(module) when is_atom(module), do: module.name()

  @doc """
  Builds a tool specification for the LLM provider.
  """
  @spec to_spec(module() | {module(), keyword()}) :: map()
  def to_spec({module, opts}) do
    %{
      name: module.name(opts),
      description: module.description(opts),
      parameters: module.parameters(opts)
    }
  end

  def to_spec(module) when is_atom(module) do
    %{
      name: module.name(),
      description: module.description(),
      parameters: module.parameters()
    }
  end

  @doc """
  Executes a tool by name with arguments.
  """
  @spec execute(module() | {module(), keyword()}, map(), context()) :: result()
  def execute({module, opts}, args, context) do
    context = Map.put(context, :opts, opts)

    try do
      module.call(args, context)
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  def execute(module, args, context) when is_atom(module) do
    context = Map.put(context, :opts, [])

    try do
      module.call(args, context)
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end
