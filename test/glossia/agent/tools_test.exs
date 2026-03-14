defmodule Glossia.Agent.ToolsTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tool
  alias Glossia.Agent.Tools.{Read, Bash, Edit, Write}

  @tmp_dir System.tmp_dir!()

  setup do
    # Create a unique test directory
    test_dir = Path.join(@tmp_dir, "glossia_agent_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    {:ok, cwd: test_dir}
  end

  describe "Tool.to_spec/1" do
    test "builds spec from module" do
      spec = Tool.to_spec(Read)
      assert spec.name == "Read"
      assert is_binary(spec.description)
      assert is_map(spec.parameters)
    end
  end

  describe "Read tool" do
    test "reads file contents", %{cwd: cwd} do
      path = Path.join(cwd, "test.txt")
      File.write!(path, "Hello, World!")

      context = %{cwd: cwd, opts: []}
      {:ok, result} = Read.call(%{"path" => "test.txt"}, context)

      assert result == "Hello, World!"
    end

    test "reads with offset and limit", %{cwd: cwd} do
      path = Path.join(cwd, "lines.txt")
      File.write!(path, "line1\nline2\nline3\nline4\nline5")

      context = %{cwd: cwd, opts: []}
      {:ok, result} = Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

      assert String.contains?(result, "line2")
      assert String.contains?(result, "line3")
      refute String.contains?(result, "line1")
      refute String.contains?(result, "line4")
    end

    test "returns error for missing file", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:error, error} = Read.call(%{"path" => "missing.txt"}, context)

      assert String.contains?(error, "not found")
    end

    test "returns error for directory", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:error, error} = Read.call(%{"path" => "."}, context)

      assert String.contains?(error, "directory")
    end
  end

  describe "Write tool" do
    test "creates new file", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, result} = Write.call(%{"path" => "new.txt", "content" => "Hello!"}, context)

      assert String.contains?(result, "Created")
      assert File.read!(Path.join(cwd, "new.txt")) == "Hello!"
    end

    test "overwrites existing file", %{cwd: cwd} do
      path = Path.join(cwd, "existing.txt")
      File.write!(path, "old content")

      context = %{cwd: cwd, opts: []}
      {:ok, result} = Write.call(%{"path" => "existing.txt", "content" => "new content"}, context)

      assert String.contains?(result, "Updated")
      assert File.read!(path) == "new content"
    end

    test "creates parent directories", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, _result} = Write.call(%{"path" => "deep/nested/file.txt", "content" => "nested"}, context)

      assert File.read!(Path.join(cwd, "deep/nested/file.txt")) == "nested"
    end
  end

  describe "Edit tool" do
    test "replaces exact text", %{cwd: cwd} do
      path = Path.join(cwd, "edit.txt")
      File.write!(path, "Hello, World!")

      context = %{cwd: cwd, opts: []}

      {:ok, result} =
        Edit.call(
          %{
            "path" => "edit.txt",
            "oldText" => "World",
            "newText" => "Elixir"
          },
          context
        )

      assert String.contains?(result, "Successfully edited")
      assert File.read!(path) == "Hello, Elixir!"
    end

    test "returns error when text not found", %{cwd: cwd} do
      path = Path.join(cwd, "edit.txt")
      File.write!(path, "Hello, World!")

      context = %{cwd: cwd, opts: []}

      {:error, error} =
        Edit.call(
          %{
            "path" => "edit.txt",
            "oldText" => "Goodbye",
            "newText" => "Hi"
          },
          context
        )

      assert String.contains?(error, "not found")
    end

    test "replaces only first occurrence", %{cwd: cwd} do
      path = Path.join(cwd, "multi.txt")
      File.write!(path, "foo bar foo bar")

      context = %{cwd: cwd, opts: []}

      {:ok, _result} =
        Edit.call(
          %{
            "path" => "multi.txt",
            "oldText" => "foo",
            "newText" => "baz"
          },
          context
        )

      assert File.read!(path) == "baz bar foo bar"
    end
  end

  describe "Bash tool" do
    test "executes simple command", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

      assert String.contains?(result, "hello")
    end

    test "captures stderr", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

      assert String.contains?(result, "error")
    end

    test "returns exit code for failures", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

      assert String.contains?(result, "exit code: 42")
    end

    test "respects cwd", %{cwd: cwd} do
      context = %{cwd: cwd, opts: []}
      {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

      assert String.contains?(result, cwd)
    end
  end
end
