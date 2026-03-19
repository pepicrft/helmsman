defmodule Helmsman.WorkspaceProviderTest do
  use ExUnit.Case, async: true

  alias Helmsman.WorkspaceProvider
  alias Helmsman.WorkspaceProvider.Snapshot
  alias Helmsman.WorkspaceProvider.Snapshot.{Source, Target}

  defmodule RecordingProvider do
    @behaviour WorkspaceProvider

    @impl true
    def snapshot(local_path, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:snapshot, local_path, opts})

      {:ok,
       %Snapshot{
         mode: :archive,
         source: %Source{
           local_path: local_path,
           root_path: local_path
         },
         target: %Target{
           path: "/runtime/project"
         }
       }}
    end

    @impl true
    def materialize(snapshot, runtime, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:materialize, snapshot, runtime, opts})
      {:ok, %{path: snapshot.target.path, runtime: runtime}}
    end

    @impl true
    def collect(runtime, workspace, local_path, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:collect, runtime, workspace, local_path, opts})
      :ok
    end
  end

  test "dispatches to a parameterized provider" do
    assert {:ok, snapshot} =
             WorkspaceProvider.snapshot(
               {RecordingProvider, test_pid: self()},
               "/tmp/project",
               source: :test
             )

    assert snapshot.source.root_path == "/tmp/project"
    assert snapshot.target.path == "/runtime/project"
    assert_receive {:snapshot, "/tmp/project", opts}
    assert opts[:test_pid] == self()
    assert opts[:source] == :test

    assert {:ok, %{path: "/runtime/project", runtime: :runtime}} =
             WorkspaceProvider.materialize(
               {RecordingProvider, test_pid: self()},
               snapshot,
               :runtime,
               source: :test
             )

    assert_receive {:materialize, ^snapshot, :runtime, materialize_opts}
    assert materialize_opts[:test_pid] == self()
    assert materialize_opts[:source] == :test

    assert :ok =
             WorkspaceProvider.collect(
               {RecordingProvider, test_pid: self()},
               :runtime,
               %{path: "/tmp/project"},
               "/tmp/output",
               source: :test
             )

    assert_receive {:collect, :runtime, %{path: "/tmp/project"}, "/tmp/output", collect_opts}
    assert collect_opts[:test_pid] == self()
    assert collect_opts[:source] == :test
  end

  test "local provider snapshots and materializes the current path" do
    assert {:ok, snapshot} = WorkspaceProvider.Local.snapshot(".", [])
    assert snapshot.mode == :local
    assert Path.type(snapshot.source.root_path) == :absolute

    assert {:ok, %{path: path, snapshot: ^snapshot}} =
             WorkspaceProvider.Local.materialize(snapshot, :runtime, [])

    assert path == snapshot.source.root_path
    assert :ok = WorkspaceProvider.Local.collect(:runtime, %{path: path}, ".", [])
  end
end
