defmodule Condukt.E2E.SandboxDaytonaTest do
  @moduledoc """
  End-to-end test that runs a simple agent workflow inside a Daytona sandbox.

  Requires DAYTONA_API_KEY environment variable.
  Run with: mix test test/e2e/sandbox_daytona_test.exs --include e2e
  """
  use ExUnit.Case, async: false

  @moduletag :e2e

  defmodule EchoAgent do
    @moduledoc false
    use Condukt

    @impl true
    def tools, do: [Condukt.Tools.Bash]

    @impl true
    def system_prompt, do: "You are a helpful assistant. When asked to run a command, use the bash tool."

    @impl true
    def model, do: "anthropic:claude-sonnet-4-20250514"
  end

  @tag timeout: to_timeout(minute: 5)
  test "agent executes bash tool inside a Daytona sandbox" do
    api_key = System.fetch_env!("DAYTONA_API_KEY")

    sandbox_config = %{
      provider: Terrarium.Providers.Daytona,
      provider_opts: [api_key: api_key]
    }

    # Start agent with sandbox
    {:ok, agent} =
      EchoAgent.start_link(
        sandbox: sandbox_config,
        api_key: System.fetch_env!("ANTHROPIC_API_KEY")
      )

    try do
      # Ask the agent to run a simple command in the sandbox
      {:ok, response} = Condukt.Session.run(agent, "Run `echo hello_from_sandbox` and tell me what it printed.")

      assert is_binary(response)
      assert response =~ "hello_from_sandbox"
    after
      GenServer.stop(agent)
    end
  end

  @tag timeout: to_timeout(minute: 3)
  test "Terrarium.Runtime.run/2 starts a peer node in Daytona sandbox" do
    api_key = System.fetch_env!("DAYTONA_API_KEY")

    # Create sandbox
    {:ok, sandbox} = Terrarium.create(Terrarium.Providers.Daytona, api_key: api_key)

    try do
      # Run ourselves in the sandbox
      {:ok, pid, node} = Terrarium.Runtime.run(sandbox)

      try do
        # Verify the remote node is connected and running
        assert Node.ping(node) == :pong

        # Execute a simple function on the remote node
        result = :erpc.call(node, System, :cmd, ["echo", ["hello_from_peer"]])
        assert {"hello_from_peer\n", 0} = result

        # Verify OTP version matches
        remote_otp = :erpc.call(node, :erlang, :system_info, [:otp_release]) |> List.to_string()
        local_otp = :erlang.system_info(:otp_release) |> List.to_string()
        assert remote_otp == local_otp
      after
        Terrarium.Runtime.stop(pid)
      end
    after
      Terrarium.destroy(sandbox)
    end
  end
end
