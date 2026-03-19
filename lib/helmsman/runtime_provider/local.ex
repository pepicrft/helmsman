defmodule Helmsman.RuntimeProvider.Local do
  @moduledoc """
  Default runtime provider that executes tools against the local machine.
  """

  @behaviour Helmsman.RuntimeProvider

  @impl true
  def init(opts) do
    {:ok, %{cwd: Keyword.fetch!(opts, :cwd)}}
  end

  @impl true
  def terminate(_session), do: :ok
end
