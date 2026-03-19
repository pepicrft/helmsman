defmodule Helmsman.WorkspaceProvider.Local do
  @moduledoc """
  Local workspace provider used when execution stays on the current machine.

  This provider keeps the current workspace in place and returns a snapshot that
  points at the existing directory instead of copying files elsewhere.
  """

  @behaviour Helmsman.WorkspaceProvider

  alias Helmsman.WorkspaceProvider.Snapshot

  @impl true
  def snapshot(local_path, _opts) do
    absolute_path = Path.expand(local_path)

    {:ok,
     %Snapshot{
       mode: :local,
       local_path: absolute_path,
       root_path: absolute_path,
       remote_path: absolute_path
     }}
  end

  @impl true
  def materialize(%Snapshot{} = snapshot, _runtime, _opts) do
    {:ok,
     %{
       path: snapshot.remote_path || snapshot.root_path,
       snapshot: snapshot
     }}
  end

  @impl true
  def collect(_runtime, _workspace, _local_path, _opts), do: :ok
end
