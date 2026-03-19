defmodule Helmsman.WorkspaceProvider do
  @moduledoc """
  Behaviour for moving workspace state between the local machine and a runtime.

  Workspace providers answer a different question than runtime providers:

  - `Helmsman.RuntimeProvider` provisions compute and execution environments
  - `Helmsman.WorkspaceProvider` snapshots, reconstructs, and optionally
    collects filesystem state for a session

  This separation keeps remote execution reproducible. A workspace provider
  can describe a repository-backed workspace, a tarball upload, or another
  transport format without changing how Helmsman runs the session itself.
  """

  defmodule FileEntry do
    @moduledoc """
    Serializable file entry included in a workspace snapshot.
    """

    @type t :: %__MODULE__{
            path: String.t(),
            content: binary(),
            mode: non_neg_integer() | nil
          }

    defstruct [:path, :content, mode: nil]
  end

  defmodule Snapshot do
    @moduledoc """
    Serializable description of a workspace to materialize in a runtime.
    """

    @type mode :: :local | :git | :archive

    @type t :: %__MODULE__{
            mode: mode(),
            local_path: String.t(),
            root_path: String.t(),
            remote_path: String.t() | nil,
            repository_url: String.t() | nil,
            revision: String.t() | nil,
            patch: String.t() | nil,
            files: [Helmsman.WorkspaceProvider.FileEntry.t()],
            metadata: map()
          }

    defstruct [
      :mode,
      :local_path,
      :root_path,
      :remote_path,
      :repository_url,
      :revision,
      :patch,
      files: [],
      metadata: %{}
    ]
  end

  @type snapshot :: Snapshot.t()
  @type workspace :: map()
  @type spec :: module() | {module(), keyword()}

  @callback snapshot(String.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  @callback materialize(snapshot(), runtime :: term(), keyword()) ::
              {:ok, workspace()} | {:error, term()}
  @callback collect(runtime :: term(), workspace(), String.t(), keyword()) ::
              :ok | {:error, term()}

  @spec snapshot(spec(), String.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def snapshot(provider, local_path, default_opts \\ [])

  def snapshot({module, opts}, local_path, default_opts) do
    module.snapshot(local_path, Keyword.merge(default_opts, opts))
  end

  def snapshot(module, local_path, default_opts) when is_atom(module) do
    module.snapshot(local_path, default_opts)
  end

  @spec materialize(spec(), snapshot(), term(), keyword()) ::
          {:ok, workspace()} | {:error, term()}
  def materialize(provider, snapshot, runtime, default_opts \\ [])

  def materialize({module, opts}, snapshot, runtime, default_opts) do
    module.materialize(snapshot, runtime, Keyword.merge(default_opts, opts))
  end

  def materialize(module, snapshot, runtime, default_opts) when is_atom(module) do
    module.materialize(snapshot, runtime, default_opts)
  end

  @spec collect(spec(), term(), workspace(), String.t(), keyword()) :: :ok | {:error, term()}
  def collect(provider, runtime, workspace, local_path, default_opts \\ [])

  def collect({module, opts}, runtime, workspace, local_path, default_opts) do
    module.collect(runtime, workspace, local_path, Keyword.merge(default_opts, opts))
  end

  def collect(module, runtime, workspace, local_path, default_opts) when is_atom(module) do
    module.collect(runtime, workspace, local_path, default_opts)
  end
end
