defmodule Helmsman.SessionStore do
  @moduledoc """
  Behaviour for persisting and restoring Helmsman sessions.

  Session stores receive the current session snapshot and decide how to
  persist it. Helmsman ships with memory and disk-backed implementations,
  and callers can provide their own store modules.
  """

  alias Helmsman.Message

  defmodule Snapshot do
    @moduledoc """
    Serializable session snapshot persisted by session stores.
    """

    @type t :: %__MODULE__{
            messages: [Message.t()],
            model: String.t() | nil,
            thinking_level: Helmsman.thinking_level() | nil,
            system_prompt: String.t() | nil
          }

    defstruct messages: [],
              model: nil,
              thinking_level: nil,
              system_prompt: nil
  end

  @type spec :: module() | {module(), keyword()}

  @callback load(keyword()) :: {:ok, Snapshot.t()} | :not_found | {:error, term()}
  @callback save(Snapshot.t(), keyword()) :: :ok | {:error, term()}
  @callback clear(keyword()) :: :ok | {:error, term()}

  @spec load(spec(), keyword()) :: {:ok, Snapshot.t()} | :not_found | {:error, term()}
  def load(store, default_opts \\ [])

  def load({module, opts}, default_opts) do
    module.load(Keyword.merge(default_opts, opts))
  end

  def load(module, default_opts) when is_atom(module) do
    module.load(default_opts)
  end

  @spec save(spec(), Snapshot.t(), keyword()) :: :ok | {:error, term()}
  def save(store, snapshot, default_opts \\ [])

  def save({module, opts}, snapshot, default_opts) do
    module.save(snapshot, Keyword.merge(default_opts, opts))
  end

  def save(module, snapshot, default_opts) when is_atom(module) do
    module.save(snapshot, default_opts)
  end

  @spec clear(spec(), keyword()) :: :ok | {:error, term()}
  def clear(store, default_opts \\ [])

  def clear({module, opts}, default_opts) do
    module.clear(Keyword.merge(default_opts, opts))
  end

  def clear(module, default_opts) when is_atom(module) do
    module.clear(default_opts)
  end
end
