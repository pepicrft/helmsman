defmodule Glossia.Agent.Tools.Read do
  @moduledoc """
  Tool for reading file contents.

  Supports text files and images (jpg, png, gif, webp). Images are returned
  as base64-encoded attachments. Text files are truncated to reasonable limits.

  ## Parameters

  - `path` - Path to the file (relative or absolute)
  - `offset` - Line number to start reading from (1-indexed, optional)
  - `limit` - Maximum number of lines to read (optional)

  ## Limits

  Output is truncated to 2000 lines or 50KB, whichever comes first.
  For large files, use offset/limit to read in chunks.
  """

  use Glossia.Agent.Tool

  @max_lines 2000
  @max_bytes 50 * 1024
  @image_extensions ~w(.jpg .jpeg .png .gif .webp)

  @impl true
  def name, do: "Read"

  @impl true
  def description do
    """
    Read the contents of a file. Supports text files and images (jpg, png, gif, webp).
    Images are sent as attachments. For text files, output is truncated to #{@max_lines} lines
    or #{div(@max_bytes, 1024)}KB. Use offset/limit for large files.
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
          description: "Path to the file to read (relative or absolute)"
        },
        offset: %{
          type: "number",
          description: "Line number to start reading from (1-indexed)"
        },
        limit: %{
          type: "number",
          description: "Maximum number of lines to read"
        }
      },
      required: ["path"]
    }
  end

  @impl true
  def call(%{"path" => path} = args, context) do
    cwd = context[:cwd] || File.cwd!()
    absolute_path = expand_path(path, cwd)
    offset = args["offset"]
    limit = args["limit"]

    case File.stat(absolute_path) do
      {:ok, %File.Stat{type: :regular}} ->
        if image?(absolute_path) do
          read_image(absolute_path)
        else
          read_text(absolute_path, offset, limit)
        end

      {:ok, %File.Stat{type: :directory}} ->
        {:error, "#{path} is a directory, not a file"}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end

  defp expand_path(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(cwd, path)
    end
  end

  defp image?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @image_extensions
  end

  defp read_image(path) do
    case File.read(path) do
      {:ok, data} ->
        media_type = media_type_for(path)

        {:ok,
         %{
           type: :image,
           media_type: media_type,
           data: Base.encode64(data)
         }}

      {:error, reason} ->
        {:error, "Cannot read image: #{inspect(reason)}"}
    end
  end

  defp media_type_for(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> case do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  defp read_text(path, offset, limit) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        total_lines = length(lines)

        {selected_lines, from_line, to_line} = select_lines(lines, offset, limit)

        {output, truncated?} = truncate_output(selected_lines)

        result = build_result(output, total_lines, from_line, to_line, truncated?)
        {:ok, result}

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  defp select_lines(lines, nil, nil) do
    {lines, 1, length(lines)}
  end

  defp select_lines(lines, offset, nil) when is_integer(offset) and offset > 0 do
    selected = Enum.drop(lines, offset - 1)
    {selected, offset, offset + length(selected) - 1}
  end

  defp select_lines(lines, nil, limit) when is_integer(limit) and limit > 0 do
    selected = Enum.take(lines, limit)
    {selected, 1, length(selected)}
  end

  defp select_lines(lines, offset, limit) when is_integer(offset) and offset > 0 and is_integer(limit) and limit > 0 do
    selected = lines |> Enum.drop(offset - 1) |> Enum.take(limit)
    {selected, offset, offset + length(selected) - 1}
  end

  defp select_lines(lines, _, _) do
    {lines, 1, length(lines)}
  end

  defp truncate_output(lines) do
    # First, limit by line count
    {lines, line_truncated?} =
      if length(lines) > @max_lines do
        {Enum.take(lines, @max_lines), true}
      else
        {lines, false}
      end

    # Then, limit by byte size
    {content, byte_truncated?} = truncate_by_bytes(lines)

    {content, line_truncated? or byte_truncated?}
  end

  defp truncate_by_bytes(lines) do
    {result, _, truncated?} =
      Enum.reduce_while(lines, {[], 0, false}, fn line, {acc, size, _} ->
        line_size = byte_size(line) + 1

        if size + line_size > @max_bytes do
          {:halt, {acc, size, true}}
        else
          {:cont, {[line | acc], size + line_size, false}}
        end
      end)

    {result |> Enum.reverse() |> Enum.join("\n"), truncated?}
  end

  defp build_result(content, total_lines, from_line, to_line, truncated?) do
    meta =
      if truncated? do
        "(showing lines #{from_line}-#{to_line} of #{total_lines}, output truncated)"
      else
        if from_line > 1 or to_line < total_lines do
          "(lines #{from_line}-#{to_line} of #{total_lines})"
        end
      end

    if meta do
      Enum.join([meta, content], "\n\n")
    else
      content
    end
  end
end
