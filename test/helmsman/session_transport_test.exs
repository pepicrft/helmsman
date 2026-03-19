defmodule Helmsman.SessionTransportTest do
  use ExUnit.Case, async: true

  alias Helmsman.SessionTransport
  alias Helmsman.Worker.SessionSpec

  defmodule RecordingTransport do
    @behaviour SessionTransport

    @impl true
    def create_session(endpoint, session_spec, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:create_session, endpoint, session_spec, opts})
      {:ok, :remote_session}
    end

    @impl true
    def run(endpoint, remote_session, prompt, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:run, endpoint, remote_session, prompt, opts})
      {:ok, "ok"}
    end

    @impl true
    def stream(endpoint, remote_session, prompt, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:stream, endpoint, remote_session, prompt, opts})
      {:ok, [%{event: :done}]}
    end

    @impl true
    def abort(endpoint, remote_session, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:abort, endpoint, remote_session, opts})
      :ok
    end

    @impl true
    def destroy_session(endpoint, remote_session, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:destroy_session, endpoint, remote_session, opts})
      :ok
    end
  end

  test "dispatches to a parameterized transport" do
    session_spec = %SessionSpec{agent_module: Helmsman.SessionTest.ConfigAgent, cwd: "/tmp/project"}

    assert {:ok, :remote_session} =
             SessionTransport.create_session(
               {RecordingTransport, test_pid: self()},
               :endpoint,
               session_spec,
               source: :test
             )

    assert_receive {:create_session, :endpoint, ^session_spec, create_opts}
    assert create_opts[:test_pid] == self()
    assert create_opts[:source] == :test

    assert {:ok, "ok"} =
             SessionTransport.run(
               {RecordingTransport, test_pid: self()},
               :endpoint,
               :remote_session,
               "hello",
               source: :test
             )

    assert_receive {:run, :endpoint, :remote_session, "hello", run_opts}
    assert run_opts[:test_pid] == self()
    assert run_opts[:source] == :test

    assert {:ok, [%{event: :done}]} =
             SessionTransport.stream(
               {RecordingTransport, test_pid: self()},
               :endpoint,
               :remote_session,
               "hello",
               source: :test
             )

    assert_receive {:stream, :endpoint, :remote_session, "hello", stream_opts}
    assert stream_opts[:test_pid] == self()
    assert stream_opts[:source] == :test

    assert :ok =
             SessionTransport.abort(
               {RecordingTransport, test_pid: self()},
               :endpoint,
               :remote_session,
               source: :test
             )

    assert_receive {:abort, :endpoint, :remote_session, abort_opts}
    assert abort_opts[:test_pid] == self()
    assert abort_opts[:source] == :test

    assert :ok =
             SessionTransport.destroy_session(
               {RecordingTransport, test_pid: self()},
               :endpoint,
               :remote_session,
               source: :test
             )

    assert_receive {:destroy_session, :endpoint, :remote_session, destroy_opts}
    assert destroy_opts[:test_pid] == self()
    assert destroy_opts[:source] == :test
  end
end
