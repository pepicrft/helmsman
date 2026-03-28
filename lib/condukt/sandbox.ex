defmodule Condukt.Sandbox do
  @moduledoc """
  Manages sandbox environments for remote agent execution.

  When a sandbox is configured, the entire agent session runs in a remote
  sandbox — LLM calls, tool execution, message history, everything. The local
  process is just a thin proxy that forwards calls to the remote session via
  `:peer.call`.

  The sandbox is provisioned via Terrarium, and the current BEAM runtime is
  replicated into it using `Terrarium.replicate/2`.

  ## Configuration

      MyAgent.start_link(
        api_key: "sk-...",
        sandbox: %{
          provider: Terrarium.Providers.Exe,
          provider_opts: [token: "exe0.xxx"]
        }
      )
  """

  use GenServer

  require Logger

  defstruct [:terrarium_sandbox, :peer_pid, :remote_session, subscribers: []]

  @type config :: %{
          required(:provider) => module(),
          optional(:provider_opts) => keyword()
        }

  @doc """
  Starts a sandbox, replicates the runtime, and starts the agent session remotely.
  """
  def start_link(agent_module, agent_opts, sandbox_config) do
    GenServer.start_link(__MODULE__, {agent_module, agent_opts, sandbox_config})
  end

  @doc """
  Stops the sandbox, tearing down the remote session and destroying the environment.
  """
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Runs a prompt on the remote session. Same as `Condukt.Session.run/3`.
  """
  def run(pid, prompt, opts \\ []) do
    GenServer.call(pid, {:run, prompt, opts}, opts[:timeout] || 300_000)
  end

  @doc """
  Streams a prompt from the remote session.

  Collects all events on the remote and returns them as a list,
  since `:peer.call` doesn't support real-time streaming.
  """
  def stream(pid, prompt, opts \\ []) do
    GenServer.call(pid, {:stream, prompt, opts}, opts[:timeout] || 300_000)
  end

  @doc """
  Returns the conversation history from the remote session.
  """
  def history(pid) do
    GenServer.call(pid, :history)
  end

  @doc """
  Clears the remote session's conversation history.
  """
  def clear(pid) do
    GenServer.call(pid, :clear)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init({agent_module, agent_opts, sandbox_config}) do
    case provision(agent_module, agent_opts, sandbox_config) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.remote_session do
      Logger.debug("Stopping remote session")
      :peer.call(state.peer_pid, GenServer, :stop, [state.remote_session])
    end

    if state.peer_pid do
      Logger.debug("Stopping peer node")
      Terrarium.stop_replica(state.peer_pid)
    end

    if state.terrarium_sandbox do
      Logger.info("Destroying sandbox", sandbox_id: state.terrarium_sandbox.id)
      Terrarium.destroy(state.terrarium_sandbox)
    end

    :ok
  end

  # Handle the same GenServer messages as Condukt.Session so the public API
  # (Condukt.run/3, Condukt.stream/3, etc.) works transparently.

  @impl true
  def handle_call({:run, prompt, opts}, _from, state) do
    result = :peer.call(state.peer_pid, Condukt.Session, :run, [state.remote_session, prompt, opts])
    {:reply, result, state}
  catch
    kind, reason ->
      {:reply, {:error, {kind, reason}}, state}
  end

  def handle_call({:subscribe, pid, ref}, _from, state) do
    {:reply, :ok, %{state | subscribers: [{pid, ref} | Map.get(state, :subscribers, [])]}}
  end

  def handle_call(:history, _from, state) do
    result = :peer.call(state.peer_pid, Condukt.Session, :history, [state.remote_session])
    {:reply, result, state}
  catch
    kind, reason ->
      {:reply, {:error, {kind, reason}}, state}
  end

  def handle_call(:clear, _from, state) do
    result = :peer.call(state.peer_pid, Condukt.Session, :clear, [state.remote_session])
    {:reply, result, state}
  catch
    kind, reason ->
      {:reply, {:error, {kind, reason}}, state}
  end

  def handle_call(:abort, _from, state) do
    :peer.call(state.peer_pid, Condukt.Session, :abort, [state.remote_session])
    {:reply, :ok, state}
  catch
    _, _ -> {:reply, :ok, state}
  end

  def handle_call({:steer, message}, _from, state) do
    :peer.call(state.peer_pid, Condukt.Session, :steer, [state.remote_session, message])
    {:reply, :ok, state}
  catch
    _, _ -> {:reply, :ok, state}
  end

  def handle_call({:follow_up, message}, _from, state) do
    :peer.call(state.peer_pid, Condukt.Session, :follow_up, [state.remote_session, message])
    {:reply, :ok, state}
  catch
    _, _ -> {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:stream, prompt, opts, subscriber_ref}, state) do
    # Run the stream on the remote, collect events, and replay to the subscriber
    parent = self()

    Task.start(fn ->
      events =
        :peer.call(
          state.peer_pid,
          __MODULE__,
          :collect_stream,
          [state.remote_session, prompt, opts]
        )

      for event <- events do
        send(parent, {:replay_event, event, subscriber_ref})
      end

      send(parent, {:replay_done, subscriber_ref})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:replay_event, event, ref}, state) do
    for {pid, ^ref} <- Map.get(state, :subscribers, []) do
      send(pid, {ref, event})
    end

    {:noreply, state}
  end

  def handle_info({:replay_done, ref}, state) do
    for {pid, ^ref} <- Map.get(state, :subscribers, []) do
      send(pid, {ref, :done})
    end

    subscribers = Enum.reject(Map.get(state, :subscribers, []), fn {_, r} -> r == ref end)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Remote Helpers (executed on the peer node)
  # ============================================================================

  @doc false
  def collect_stream(session, prompt, opts) do
    Condukt.Session.stream(session, prompt, opts)
    |> Enum.to_list()
  end

  # ============================================================================
  # Provisioning
  # ============================================================================

  defp provision(agent_module, agent_opts, sandbox_config) do
    provider = Map.fetch!(sandbox_config, :provider)
    provider_opts = Map.get(sandbox_config, :provider_opts, [])

    with {:ok, sandbox} <- Terrarium.create(provider, provider_opts),
         {:ok, peer_pid, _node} <- Terrarium.replicate(sandbox),
         {:ok, remote_session} <- start_remote_session(peer_pid, agent_module, agent_opts) do
      Logger.info("Sandbox provisioned with remote session",
        sandbox_id: sandbox.id,
        provider: provider
      )

      {:ok,
       %__MODULE__{
         terrarium_sandbox: sandbox,
         peer_pid: peer_pid,
         remote_session: remote_session
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to provision sandbox", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp start_remote_session(peer_pid, agent_module, agent_opts) do
    # Remove sandbox config to avoid infinite recursion on the remote
    agent_opts = Keyword.delete(agent_opts, :sandbox)

    Logger.debug("Starting remote session", agent_module: agent_module)

    case :peer.call(peer_pid, Condukt.Session, :start_link, [agent_module, agent_opts]) do
      {:ok, remote_session} ->
        Logger.info("Remote session started")
        {:ok, remote_session}

      {:error, reason} ->
        {:error, {:remote_session_failed, reason}}
    end
  end
end
