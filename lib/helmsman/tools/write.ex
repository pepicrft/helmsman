defmodule Helmsman.Tools.Write do
  @moduledoc """
  Tool for writing content to files.

  Creates the file if it doesn't exist, overwrites if it does.
  Automatically creates parent directories as needed.

  ## Parameters

  - `path` - Path to the file to write
  - `content` - Content to write to the file
  """

  use Helmsman.Tool

  @impl true
  def name, do: "Write"

  @impl true
  def description do
    """
    Write content to a file. Creates the file if it doesn't exist, overwrites if it does.
    Automatically creates parent directories.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Path to the file to write (relative or absolute)"
        },
        content: %{
          type: "string",
          description: "Content to write to the file"
        }
      },
      required: ["path", "content"]
    }
  end

  @impl true
  def call(%{"path" => path, "content" => content}, context) do
    cwd = context[:cwd] || File.cwd!()
    absolute_path = expand_path(path, cwd)

    # Ensure parent directory exists
    dir = Path.dirname(absolute_path)

    case File.mkdir_p(dir) do
      :ok ->
        write_file(absolute_path, content, path)

      {:error, reason} ->
        {:error, "Cannot create directory #{dir}: #{inspect(reason)}"}
    end
  end

  defp expand_path(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(cwd, path)
    end
  end

  defp write_file(absolute_path, content, display_path) do
    existed? = File.exists?(absolute_path)

    case File.write(absolute_path, content) do
      :ok ->
        bytes = byte_size(content)
        lines = content |> String.split("\n") |> length()

        action = if existed?, do: "Updated", else: "Created"

        {:ok, "#{action} #{display_path} (#{lines} lines, #{bytes} bytes)"}

      {:error, reason} ->
        {:error, "Cannot write to #{display_path}: #{inspect(reason)}"}
    end
  end
end
