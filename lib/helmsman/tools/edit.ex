defmodule Helmsman.Tools.Edit do
  @moduledoc """
  Tool for making surgical edits to files.

  Finds exact text in a file and replaces it with new text.
  The old_text must match exactly, including whitespace.

  ## Parameters

  - `path` - Path to the file to edit
  - `old_text` - Exact text to find and replace (must match exactly)
  - `new_text` - New text to replace the old text with

  ## Notes

  - The match is exact and case-sensitive
  - Whitespace and indentation must match exactly
  - The target text must appear exactly once
  - For multiple replacements, provide more context to make each match unique
  """

  use Helmsman.Tool

  @impl true
  def name, do: "Edit"

  @impl true
  def description do
    """
    Edit a file by replacing exact text. The old_text must match exactly (including whitespace).
    Use this for precise, surgical edits.
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
          description: "Path to the file to edit (relative or absolute)"
        },
        old_text: %{
          type: "string",
          description: "Exact text to find and replace (must match exactly)"
        },
        new_text: %{
          type: "string",
          description: "New text to replace the old text with"
        }
      },
      required: ["path", "old_text", "new_text"]
    }
  end

  @impl true
  def call(%{"path" => path, "old_text" => old_text, "new_text" => new_text}, context) do
    cwd = context[:cwd] || File.cwd!()
    absolute_path = expand_path(path, cwd)

    case File.read(absolute_path) do
      {:ok, content} ->
        case count_occurrences(content, old_text) do
          0 ->
            {:error, find_similar_text(content, old_text, path)}

          1 ->
            apply_edit(content, old_text, new_text, absolute_path, path)

          count ->
            {:error,
             "Found #{count} occurrences of old_text in #{path}. Make the match unique by including more surrounding context."}
        end

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

  defp count_occurrences(content, old_text) do
    content
    |> String.split(old_text)
    |> length()
    |> Kernel.-(1)
  end

  defp apply_edit(content, old_text, new_text, absolute_path, path) do
    {index, old_text_length} = :binary.match(content, old_text)

    new_content =
      binary_part(content, 0, index) <>
        new_text <>
        binary_part(content, index + old_text_length, byte_size(content) - index - old_text_length)

    if new_content == content do
      {:error, "No changes made to #{path}. The replacement produced identical content."}
    else
      case File.write(absolute_path, new_content) do
        :ok ->
          diff = generate_diff(old_text, new_text)
          {:ok, Enum.join(["Successfully edited #{path}", diff], "\n\n")}

        {:error, reason} ->
          {:error, "Cannot write to #{path}: #{inspect(reason)}"}
      end
    end
  end

  defp generate_diff(old_text, new_text) do
    old_lines = String.split(old_text, "\n")
    new_lines = String.split(new_text, "\n")

    diff =
      [
        Enum.map(old_lines, &"- #{&1}"),
        Enum.map(new_lines, &"+ #{&1}")
      ]
      |> List.flatten()
      |> Enum.join("\n")

    "```diff\n#{diff}\n```"
  end

  defp find_similar_text(content, old_text, path) do
    # Try to find why the match failed
    old_lines = String.split(old_text, "\n")
    first_line = List.first(old_lines) |> String.trim()

    cond do
      String.length(first_line) < 5 ->
        "old_text not found in #{path}. Make sure the text matches exactly, including whitespace."

      String.contains?(content, first_line) ->
        """
        old_text not found in #{path}.
        The first line exists in the file, but the full match failed.
        This is often caused by whitespace differences (tabs vs spaces, trailing spaces, or line endings).
        Use the Read tool to see the exact content.
        """
        |> String.trim()

      true ->
        """
        old_text not found in #{path}.
        The text you're looking for doesn't appear in the file.
        Use the Read tool to check the current file contents.
        """
        |> String.trim()
    end
  end
end
