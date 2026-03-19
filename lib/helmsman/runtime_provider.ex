defmodule Helmsman.RuntimeProvider do
  @moduledoc """
  Behaviour for provisioning execution environments for Helmsman workers.

  In the remote-worker architecture, runtime providers belong to the local
  controller boundary. They are responsible for booting and tearing down the
  environment that will host a worker, not for being passed into ordinary tools.
  """

  @type session :: term()
  @type spec :: module() | {module(), keyword()}

  @callback init(keyword()) :: {:ok, session()} | {:error, term()}
  @callback terminate(session()) :: :ok | {:error, term()}

  @spec init(spec(), keyword()) :: {:ok, session()} | {:error, term()}
  def init(provider, default_opts \\ [])

  def init({module, opts}, default_opts) do
    module.init(Keyword.merge(default_opts, opts))
  end

  def init(module, default_opts) when is_atom(module) do
    module.init(default_opts)
  end

  @spec terminate(spec(), session()) :: :ok | {:error, term()}
  def terminate(provider, session)

  def terminate({module, _opts}, session) do
    module.terminate(session)
  end

  def terminate(module, session) when is_atom(module) do
    module.terminate(session)
  end
end
