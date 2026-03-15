defmodule Helmsman.Tools.BashTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Helmsman.Tools.Bash

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "executes simple command", %{tmp_dir: tmp_dir} do
    Helmsman.Tools.Bash.MuonTrapRunner
    |> expect(:cmd, fn "bash", ["-c", "echo hello"], opts ->
      assert opts[:cd] == tmp_dir
      assert opts[:stderr_to_stdout] == true
      assert opts[:timeout] == 120_000
      assert {"TERM", "dumb"} in opts[:env]
      {"hello\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "captures stderr", %{tmp_dir: tmp_dir} do
    Helmsman.Tools.Bash.MuonTrapRunner
    |> expect(:cmd, fn "bash", ["-c", "echo error >&2"], opts ->
      assert opts[:cd] == tmp_dir
      {"error\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{tmp_dir: tmp_dir} do
    Helmsman.Tools.Bash.MuonTrapRunner
    |> expect(:cmd, fn "bash", ["-c", "exit 42"], opts ->
      assert opts[:cd] == tmp_dir
      {"", 42}
    end)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{tmp_dir: tmp_dir} do
    Helmsman.Tools.Bash.MuonTrapRunner
    |> expect(:cmd, fn "bash", ["-c", "pwd"], opts ->
      assert opts[:cd] == tmp_dir
      {"#{tmp_dir}\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, tmp_dir)
  end

  test "accepts cwd argument relative to context cwd", %{tmp_dir: tmp_dir} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    Helmsman.Tools.Bash.MuonTrapRunner
    |> expect(:cmd, fn "bash", ["-c", "pwd"], opts ->
      assert opts[:cd] == nested_dir
      {"#{nested_dir}\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd", "cwd" => "nested"}, context)

    assert String.contains?(result, nested_dir)
  end
end
