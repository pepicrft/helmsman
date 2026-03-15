defmodule Glossia.Agent.Tools.EditTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tools.Edit

  @moduletag :tmp_dir

  test "replaces exact text", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "edit.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: tmp_dir, opts: []}

    {:ok, result} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "World",
          "new_text" => "Elixir"
        },
        context
      )

    assert String.contains?(result, "Successfully edited")
    assert File.read!(path) == "Hello, Elixir!"
  end

  test "returns error when text not found", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "edit.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: tmp_dir, opts: []}

    {:error, error} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "Goodbye",
          "new_text" => "Hi"
        },
        context
      )

    assert String.contains?(error, "not found")
  end

  test "replaces only first occurrence", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "multi.txt")
    File.write!(path, "foo bar foo bar")

    context = %{cwd: tmp_dir, opts: []}

    {:ok, _result} =
      Edit.call(
        %{
          "path" => "multi.txt",
          "old_text" => "foo",
          "new_text" => "baz"
        },
        context
      )

    assert File.read!(path) == "baz bar foo bar"
  end
end
