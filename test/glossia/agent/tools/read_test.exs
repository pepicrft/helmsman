defmodule Glossia.Agent.Tools.ReadTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tools.Read

  @moduletag :tmp_dir

  test "reads file contents", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "test.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Read.call(%{"path" => "test.txt"}, context)

    assert result == "Hello, World!"
  end

  test "reads with offset and limit", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "lines.txt")
    File.write!(path, "line1\nline2\nline3\nline4\nline5")

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

    assert String.contains?(result, "line2")
    assert String.contains?(result, "line3")
    refute String.contains?(result, "line1")
    refute String.contains?(result, "line4")
  end

  test "returns error for missing file", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:error, error} = Read.call(%{"path" => "missing.txt"}, context)

    assert String.contains?(error, "not found")
  end

  test "returns error for directory", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:error, error} = Read.call(%{"path" => "."}, context)

    assert String.contains?(error, "directory")
  end
end
