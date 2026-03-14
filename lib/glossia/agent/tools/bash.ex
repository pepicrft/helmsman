defmodule Glossia.Agent.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.

  Runs commands in the current working directory and returns stdout/stderr.
  Output is truncated to reasonable limits.

  ## Parameters

  - `command` - The bash command to execute
  - `timeout` - Timeout in seconds (optional, default: 120)

  ## Safety

  This tool executes arbitrary shell commands. Use with caution and
  consider implementing allowlists or sandboxing for production use.
  """

  use Glossia.Agent.Tool

  @max_lines 2000
  @max_bytes 50 * 1024
  @default_timeout 120_000

  @impl true
  def name, do: "Bash"

  @impl true
  def description do
    """
    Execute a bash command in the current working directory. Returns stdout and stderr.
    Output is truncated to #{@max_lines} lines or #{div(@max_bytes, 1024)}KB.
    Optionally provide a timeout in seconds.
    """
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
    cwd = context[:cwd] || File.cwd!()
    timeout = (args["timeout"] || div(@default_timeout, 1000)) * 1000

    # Use Port for better control and streaming
    case execute_command(command, cwd, timeout) do
      {:ok, output, exit_code} ->
        {truncated_output, was_truncated} = truncate_output(output)

        result =
          if was_truncated do
            "#{truncated_output}\n\n(output truncated)"
          else
            truncated_output
          end

        result =
          if exit_code != 0 do
            "#{result}\n\n(exit code: #{exit_code})"
          else
            result
          end

        {:ok, result}

      {:error, :timeout} ->
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(command, cwd, timeout) do
    # Use System.cmd with stderr_to_stdout for simplicity
    task =
      Task.async(fn ->
        try do
          {output, exit_code} =
            System.cmd("bash", ["-c", command],
              cd: cwd,
              stderr_to_stdout: true,
              env: build_env()
            )

          {:ok, output, exit_code}
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp build_env do
    # Inherit current environment with some safety additions
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
