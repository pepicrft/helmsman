defmodule Helmsman.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Helmsman.Message
  alias Helmsman.SessionStore.{Disk, Memory}
  alias Helmsman.SessionStore.Snapshot

  test "memory store saves, loads, and clears snapshots" do
    key = make_ref()

    snapshot = %Snapshot{
      messages: [Message.user("hello"), Message.assistant("world")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "stored prompt"
    }

    assert Memory.load(key: key) == :not_found
    assert :ok = Memory.save(snapshot, key: key)
    assert {:ok, ^snapshot} = Memory.load(key: key)
    assert :ok = Memory.clear(key: key)
    assert Memory.load(key: key) == :not_found
  end

  test "disk store saves, loads, and clears snapshots" do
    path =
      Path.join(System.tmp_dir!(), "helmsman-session-store-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(path) end)

    snapshot = %Snapshot{
      messages: [Message.user("persist this")],
      model: "anthropic:claude-sonnet-4-20250514",
      thinking_level: :medium,
      system_prompt: "disk prompt"
    }

    assert Disk.load(path: path, cwd: "/tmp") == :not_found
    assert :ok = Disk.save(snapshot, path: path, cwd: "/tmp")
    assert {:ok, ^snapshot} = Disk.load(path: path, cwd: "/tmp")
    assert :ok = Disk.clear(path: path, cwd: "/tmp")
    assert Disk.load(path: path, cwd: "/tmp") == :not_found
  end

  test "disk store uses the default path under cwd" do
    cwd = Path.join(System.tmp_dir!(), "helmsman-cwd-#{System.unique_integer([:positive])}")
    path = Path.join([cwd, ".helmsman", "session.store"])

    on_exit(fn -> File.rm_rf(cwd) end)

    snapshot = %Snapshot{
      messages: [Message.user("persist this too")],
      model: "openai:gpt-4o-mini",
      thinking_level: :high,
      system_prompt: "default path"
    }

    assert Disk.load(cwd: cwd) == :not_found
    assert :ok = Disk.save(snapshot, cwd: cwd)
    assert File.exists?(path)
    assert {:ok, ^snapshot} = Disk.load(cwd: cwd)
  end

  test "disk store loads legacy snapshots encoded without a version wrapper" do
    path =
      Path.join(System.tmp_dir!(), "helmsman-legacy-session-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(path) end)

    snapshot = %Snapshot{
      messages: [Message.assistant("from legacy format")],
      model: "openai:gpt-4o",
      thinking_level: :low,
      system_prompt: "legacy snapshot"
    }

    assert :ok = File.write(path, :erlang.term_to_binary(snapshot))
    assert {:ok, ^snapshot} = Disk.load(path: path, cwd: "/tmp")
  end

  test "disk store returns an error for invalid snapshots" do
    path =
      Path.join(System.tmp_dir!(), "helmsman-invalid-session-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(path) end)

    assert :ok = File.write(path, "not a valid snapshot")
    assert Disk.load(path: path, cwd: "/tmp") == {:error, :invalid_snapshot}
  end

  test "disk store clear succeeds for a missing snapshot file" do
    path =
      Path.join(System.tmp_dir!(), "helmsman-missing-session-#{System.unique_integer([:positive])}")

    assert :ok = Disk.clear(path: path, cwd: "/tmp")
  end
end
