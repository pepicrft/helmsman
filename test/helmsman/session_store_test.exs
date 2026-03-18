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

  test "disk store returns an error for invalid snapshots" do
    path =
      Path.join(System.tmp_dir!(), "helmsman-invalid-session-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(path) end)

    assert :ok = File.write(path, "not a valid snapshot")
    assert Disk.load(path: path, cwd: "/tmp") == {:error, :invalid_snapshot}
  end
end
