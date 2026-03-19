defmodule Helmsman.SessionStore.Disk do
  @moduledoc """
  Disk-backed session store using Erlang term serialization.

  By default snapshots are written to `.helmsman/session.store` in the
  configured working directory. Override with `path: ...`.
  """

  @behaviour Helmsman.SessionStore

  alias Helmsman.SessionStore.Snapshot

  @version 1

  @impl true
  def load(opts) do
    path = path(opts)

    case File.read(path) do
      {:ok, binary} ->
        with {:ok, payload} <- decode(binary) do
          extract_snapshot(payload)
        end

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save(%Snapshot{} = snapshot, opts) do
    path = path(opts)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, encode(snapshot))
    end
  end

  @impl true
  def clear(opts) do
    path = path(opts)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp path(opts) do
    Keyword.get_lazy(opts, :path, fn ->
      Path.join([Keyword.fetch!(opts, :cwd), ".helmsman", "session.store"])
    end)
  end

  defp encode(snapshot) do
    :erlang.term_to_binary(%{version: @version, snapshot: snapshot})
  end

  defp decode(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  catch
    :error, _reason ->
      {:error, :invalid_snapshot}
  end

  defp extract_snapshot(%{version: @version, snapshot: %Snapshot{} = snapshot}), do: {:ok, snapshot}
  defp extract_snapshot(%Snapshot{} = snapshot), do: {:ok, snapshot}
  defp extract_snapshot(_payload), do: {:error, :invalid_snapshot}
end
