defmodule Glossia.Agent.Tools.Edit do
  @moduledoc """
  Tool for making surgical edits to files.

  Finds exact text in a file and replaces it with new text.
  The oldText must match exactly, including whitespace.

  ## Parameters

  - `path` - Path to the file to edit
  - `oldText` - Exact text to find and replace (must match exactly)
  - `newText` - New text to replace the old text with

  ## Notes

  - The match is exact and case-sensitive
  - Whitespace and indentation must match exactly
  - Only the first occurrence is replaced
  - For multiple replacements, make multiple tool calls
  """

  use Glossia.Agent.Tool

  @impl true
  def name, do: "Edit"

  @impl true
  def description do
    """
    Edit a file by replacing exact text. The oldText must match exactly (including whitespace).
    Use this for precise, surgical edits.
    """
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
        oldText: %{
          type: "string",
          description: "Exact text to find and replace (must match exactly)"
        },
        newText: %{
          type: "string",
          description: "New text to replace the old text with"
        }
      },
      required: ["path", "oldText", "newText"]
    }
  end

  @impl true
  def call(%{"path" => path, "oldText" => old_text, "newText" => new_text}, context) do
    cwd = context[:cwd] || File.cwd!()
    absolute_path = expand_path(path, cwd)

    case File.read(absolute_path) do
      {:ok, content} ->
        if String.contains?(content, old_text) do
          # Replace only the first occurrence
          new_content = String.replace(content, old_text, new_text, global: false)

          case File.write(absolute_path, new_content) do
            :ok ->
              diff = generate_diff(old_text, new_text)
              {:ok, "Successfully edited #{path}\n\n#{diff}"}

            {:error, reason} ->
              {:error, "Cannot write to #{path}: #{reason}"}
          end
        else
          # Try to provide helpful feedback
          {:error, find_similar_text(content, old_text, path)}
        end

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{reason}"}
    end
  end

  defp expand_path(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(cwd, path)
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
        "oldText not found in #{path}. Make sure the text matches exactly, including whitespace."

      String.contains?(content, first_line) ->
        # The first line exists but the full match doesn't - likely whitespace issue
        """
        oldText not found in #{path}.
        The first line exists in the file, but the full match failed.
        This is often caused by whitespace differences (tabs vs spaces, trailing spaces, or line endings).
        Use the Read tool to see the exact content.
        """

      true ->
        # First line doesn't exist at all
        """
        oldText not found in #{path}.
        The text you're looking for doesn't appear in the file.
        Use the Read tool to check the current file contents.
        """
    end
  end
end
