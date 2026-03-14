defmodule Glossia.Agent.Tools do
  @moduledoc """
  Built-in tools for Glossia.Agent.

  ## Default Tool Sets

  - `coding_tools/0` - Read, Bash, Edit, Write (default for coding agents)
  - `read_only_tools/0` - Read, Bash (read-only access)

  ## Individual Tools

  - `Glossia.Agent.Tools.Read` - Read file contents
  - `Glossia.Agent.Tools.Bash` - Execute bash commands
  - `Glossia.Agent.Tools.Edit` - Surgical file edits
  - `Glossia.Agent.Tools.Write` - Write files

  ## Usage

      defmodule MyAgent do
        use Glossia.Agent

        @impl true
        def tools do
          Glossia.Agent.Tools.coding_tools()
        end
      end

  Or pick specific tools:

      def tools do
        [
          Glossia.Agent.Tools.Read,
          Glossia.Agent.Tools.Bash
        ]
      end
  """

  alias Glossia.Agent.Tools.{Read, Bash, Edit, Write}

  @doc """
  Returns the default coding tools: Read, Bash, Edit, Write.

  These tools provide full filesystem access for coding agents.
  """
  @spec coding_tools() :: [module()]
  def coding_tools do
    [Read, Bash, Edit, Write]
  end

  @doc """
  Returns read-only tools: Read, Bash.

  Use these when you want the agent to explore but not modify files.
  Note that Bash can still execute arbitrary commands - consider
  implementing command allowlists for production.
  """
  @spec read_only_tools() :: [module()]
  def read_only_tools do
    [Read, Bash]
  end

  @doc """
  Returns all available built-in tools.
  """
  @spec all() :: [module()]
  def all do
    [Read, Bash, Edit, Write]
  end
end
