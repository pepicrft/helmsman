defmodule Condukt.E2E.SandboxExeTest do
  @moduledoc """
  End-to-end test that runs an agent inside an exe.dev sandbox.

  Requires EXE_DEV_TOKEN environment variable.
  Run with: mix test test/e2e/sandbox_exe_test.exs --include e2e
  """
  use ExUnit.Case, async: false

  @moduletag :e2e

  defmodule TestAgent do
    use Condukt

    @impl true
    def tools, do: [Condukt.Tools.Bash]

    @impl true
    def system_prompt, do: "You are a helpful assistant. When asked to run a command, use the Bash tool. Be concise."

    @impl true
    def model, do: "zai:glm-4.5-flash"

    @impl true
    def thinking_level, do: :off
  end

  @tag timeout: to_timeout(minute: 10)
  test "agent runs entirely inside exe.dev sandbox" do
    token = System.fetch_env!("EXE_DEV_TOKEN")

    # Start agent with sandbox — the entire session runs remotely
    {:ok, agent} =
      TestAgent.start_link(
        sandbox: %{
          provider: Terrarium.Providers.Exe,
          provider_opts: [token: token]
        }
      )

    try do
      # Same API as local — run a prompt
      {:ok, response} = Condukt.run(agent, "Run `uname -s` and tell me the result. Just the OS name.")

      # The sandbox runs Linux, not Darwin
      assert is_binary(response)
      assert response =~ "Linux"
    after
      GenServer.stop(agent)
    end
  end
end
