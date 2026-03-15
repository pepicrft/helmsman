defmodule Glossia.Agent.Tools.BashTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tools.Bash

  @moduletag :tmp_dir

  test "executes simple command", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "captures stderr", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, tmp_dir)
  end

  test "accepts cwd argument relative to context cwd", %{tmp_dir: tmp_dir} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd", "cwd" => "nested"}, context)

    assert String.contains?(result, nested_dir)
  end
end
