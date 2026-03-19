defmodule Helmsman.SessionTransport do
  @moduledoc """
  Behaviour for communicating with a Helmsman worker that owns the actual
  `Helmsman.Session`.

  A session transport is responsible for the user-facing control plane:

  - create a worker-side session
  - run prompts and receive responses
  - stream structured events back to the caller
  - abort or destroy the remote session

  This keeps the transport protocol separate from runtime provisioning and
  workspace synchronization.
  """

  @type endpoint :: term()
  @type remote_session :: term()
  @type stream :: Enumerable.t()
  @type spec :: module() | {module(), keyword()}

  @callback create_session(endpoint(), Helmsman.Worker.SessionSpec.t(), keyword()) ::
              {:ok, remote_session()} | {:error, term()}
  @callback run(endpoint(), remote_session(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback stream(endpoint(), remote_session(), String.t(), keyword()) ::
              {:ok, stream()} | {:error, term()}
  @callback abort(endpoint(), remote_session(), keyword()) :: :ok | {:error, term()}
  @callback destroy_session(endpoint(), remote_session(), keyword()) :: :ok | {:error, term()}

  @spec create_session(spec(), endpoint(), Helmsman.Worker.SessionSpec.t(), keyword()) ::
          {:ok, remote_session()} | {:error, term()}
  def create_session(transport, endpoint, session_spec, default_opts \\ [])

  def create_session({module, opts}, endpoint, session_spec, default_opts) do
    module.create_session(endpoint, session_spec, Keyword.merge(default_opts, opts))
  end

  def create_session(module, endpoint, session_spec, default_opts) when is_atom(module) do
    module.create_session(endpoint, session_spec, default_opts)
  end

  @spec run(spec(), endpoint(), remote_session(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run(transport, endpoint, remote_session, prompt, default_opts \\ [])

  def run({module, opts}, endpoint, remote_session, prompt, default_opts) do
    module.run(endpoint, remote_session, prompt, Keyword.merge(default_opts, opts))
  end

  def run(module, endpoint, remote_session, prompt, default_opts) when is_atom(module) do
    module.run(endpoint, remote_session, prompt, default_opts)
  end

  @spec stream(spec(), endpoint(), remote_session(), String.t(), keyword()) ::
          {:ok, stream()} | {:error, term()}
  def stream(transport, endpoint, remote_session, prompt, default_opts \\ [])

  def stream({module, opts}, endpoint, remote_session, prompt, default_opts) do
    module.stream(endpoint, remote_session, prompt, Keyword.merge(default_opts, opts))
  end

  def stream(module, endpoint, remote_session, prompt, default_opts) when is_atom(module) do
    module.stream(endpoint, remote_session, prompt, default_opts)
  end

  @spec abort(spec(), endpoint(), remote_session(), keyword()) :: :ok | {:error, term()}
  def abort(transport, endpoint, remote_session, default_opts \\ [])

  def abort({module, opts}, endpoint, remote_session, default_opts) do
    module.abort(endpoint, remote_session, Keyword.merge(default_opts, opts))
  end

  def abort(module, endpoint, remote_session, default_opts) when is_atom(module) do
    module.abort(endpoint, remote_session, default_opts)
  end

  @spec destroy_session(spec(), endpoint(), remote_session(), keyword()) :: :ok | {:error, term()}
  def destroy_session(transport, endpoint, remote_session, default_opts \\ [])

  def destroy_session({module, opts}, endpoint, remote_session, default_opts) do
    module.destroy_session(endpoint, remote_session, Keyword.merge(default_opts, opts))
  end

  def destroy_session(module, endpoint, remote_session, default_opts) when is_atom(module) do
    module.destroy_session(endpoint, remote_session, default_opts)
  end
end
