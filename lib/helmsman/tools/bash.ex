defmodule Helmsman.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.

  Runs commands in the current working directory and returns stdout/stderr.
  Output is truncated to reasonable limits.

  ## Parameters

  - `command` - The bash command to execute
  - `cwd` - Directory to run the command in (optional)
  - `timeout` - Timeout in seconds (optional, default: 120)

  ## Safety

  This tool executes arbitrary shell commands. Use with caution and
  consider implementing allowlists or sandboxing for production use.
  """

  use Helmsman.Tool

  @max_lines 2000
  @max_bytes 50 * 1024
  @default_timeout 120_000

  defmodule CommandRunner do
    @callback cmd(binary(), [binary()], keyword()) :: {Collectable.t(), non_neg_integer() | :timeout}
  end

  defmodule MuonTrapRunner do
    @behaviour CommandRunner

    @impl true
    def cmd(command, args, opts), do: MuonTrap.cmd(command, args, opts)
  end

  @impl true
  def name, do: "Bash"

  @impl true
  def description do
    """
    Execute a bash command in the current working directory. Returns stdout and stderr.
    Output is truncated to #{@max_lines} lines or #{div(@max_bytes, 1024)}KB.
    Optionally provide a cwd and timeout in seconds.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        command: %{
          type: "string",
          description: "Bash command to execute"
        },
        cwd: %{
          type: "string",
          description: "Directory to run the command in (relative or absolute)"
        },
        timeout: %{
          type: "number",
          description: "Timeout in seconds (optional, default: #{div(@default_timeout, 1000)})"
        }
      },
      required: ["command"]
    }
  end

  @impl true
  def call(%{"command" => command} = args, context) do
    base_cwd = context[:cwd] || File.cwd!()
    cwd = resolve_cwd(args["cwd"], base_cwd)
    timeout = trunc((args["timeout"] || div(@default_timeout, 1000)) * 1000)

    case execute_command(command, cwd, timeout) do
      {:ok, output, exit_code} ->
        {truncated_output, truncated?} = truncate_output(output)

        result =
          [
            truncated_output,
            truncated? && "(output truncated)",
            exit_code != 0 && "(exit code: #{exit_code})"
          ]
          |> Enum.reject(&(&1 in [false, nil, ""]))
          |> Enum.join("\n\n")

        {:ok, result}

      {:error, :timeout} ->
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  defp resolve_cwd(nil, cwd), do: cwd

  defp resolve_cwd(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, cwd)
    end
  end

  defp execute_command(command, cwd, timeout) do
    case MuonTrapRunner.cmd("bash", ["-c", command],
           cd: cwd,
           stderr_to_stdout: true,
           env: build_env(),
           timeout: timeout
         ) do
      {_output, :timeout} -> {:error, :timeout}
      {output, exit_code} -> {:ok, output, exit_code}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp build_env do
    [
      {"TERM", "dumb"},
      {"PAGER", "cat"},
      {"GIT_PAGER", "cat"}
    ]
  end

  defp truncate_output(output) do
    lines = String.split(output, "\n")

    {lines, truncated_by_lines?} =
      if length(lines) > @max_lines do
        {Enum.take(lines, @max_lines), true}
      else
        {lines, false}
      end

    content = Enum.join(lines, "\n")

    {content, truncated_by_bytes?} =
      if byte_size(content) > @max_bytes do
        {String.slice(content, 0, @max_bytes), true}
      else
        {content, false}
      end

    {content, truncated_by_lines? or truncated_by_bytes?}
  end
end
