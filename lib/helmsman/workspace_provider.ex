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

    A snapshot is the boundary between "workspace state as it exists now" and
    "workspace state that can be recreated elsewhere later".

    The fields are grouped by concern:

    - `mode` describes the reconstruction strategy
    - `source` describes where the workspace came from
    - `target` describes where the workspace should be materialized
    - `git` carries repository-specific reconstruction data
    - `files` carries explicit file payloads when content must be shipped
    - `metadata` is reserved for provider-specific extensions

    Example shapes:

    - Local execution:
      `%Snapshot{
        mode: :local,
        source: %{local_path: "/repo", root_path: "/repo"},
        target: %{path: "/repo"}
      }`

    - Remote git reconstruction:
      `%Snapshot{
        mode: :git,
        source: %{local_path: "/repo", root_path: "/repo"},
        target: %{path: "/workspace/repo"},
        git: %{repository_url: "...", revision: "abc123", patch: "..."}
      }`
    """

    @type mode :: :local | :git | :archive

    defmodule Source do
      @moduledoc """
      Origin information for the workspace represented by a snapshot.

      - `local_path` is the path provided by the caller
      - `root_path` is the canonical workspace root captured by the snapshot
      """

      @type t :: %__MODULE__{
              local_path: String.t(),
              root_path: String.t()
            }

      defstruct [:local_path, :root_path]
    end

    defmodule Target do
      @moduledoc """
      Materialization information for a workspace snapshot.

      `path` is the directory where the snapshot should exist once it has been
      reconstructed in a runtime.
      """

      @type t :: %__MODULE__{
              path: String.t() | nil
            }

      defstruct [:path]
    end

    defmodule Git do
      @moduledoc """
      Repository metadata for git-backed workspace reconstruction.

      - `repository_url` is the source repository to clone
      - `revision` is the base commit or ref to check out
      - `patch` is the diff to apply on top of that base
      """

      @type t :: %__MODULE__{
              repository_url: String.t() | nil,
              revision: String.t() | nil,
              patch: String.t() | nil
            }

      defstruct [:repository_url, :revision, :patch]
    end

    @type t :: %__MODULE__{
            mode: mode(),
            source: Source.t(),
            target: Target.t(),
            git: Git.t() | nil,
            files: [Helmsman.WorkspaceProvider.FileEntry.t()],
            metadata: map()
          }

    defstruct [
      :mode,
      :source,
      :target,
      :git,
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
