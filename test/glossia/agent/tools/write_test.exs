defmodule Glossia.Agent.Tools.WriteTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tools.Write

  @moduletag :tmp_dir

  test "creates new file", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Write.call(%{"path" => "new.txt", "content" => "Hello!"}, context)

    assert String.contains?(result, "Created")
    assert File.read!(Path.join(tmp_dir, "new.txt")) == "Hello!"
  end

  test "overwrites existing file", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "existing.txt")
    File.write!(path, "old content")

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Write.call(%{"path" => "existing.txt", "content" => "new content"}, context)

    assert String.contains?(result, "Updated")
    assert File.read!(path) == "new content"
  end

  test "creates parent directories", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, _result} = Write.call(%{"path" => "deep/nested/file.txt", "content" => "nested"}, context)

    assert File.read!(Path.join(tmp_dir, "deep/nested/file.txt")) == "nested"
  end
end
