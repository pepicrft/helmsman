defmodule Helmsman.Telemetry do
  @moduledoc """
  Telemetry integration for Helmsman.

  Helmsman emits telemetry events that can be used for monitoring,
  logging, and observability.

  ## Events

  ### Agent Events

  - `[:helmsman, :agent, :start]` - Agent started processing a prompt
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module}`

  - `[:helmsman, :agent, :stop]` - Agent finished processing
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module}`

  - `[:helmsman, :agent, :exception]` - Agent raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, kind: atom, reason: term, stacktrace: list}`

  ### Tool Events

  - `[:helmsman, :tool_call, :start]` - Tool call started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{tool: string}`

  - `[:helmsman, :tool_call, :stop]` - Tool call completed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string}`

  - `[:helmsman, :tool_call, :exception]` - Tool call raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string, kind: atom, reason: term, stacktrace: list}`

  ## Example: Attaching Handlers

      :telemetry.attach_many(
        "my-agent-handler",
        [
          [:helmsman, :agent, :start],
          [:helmsman, :agent, :stop],
          [:helmsman, :tool_call, :stop]
        ],
        &MyApp.Telemetry.handle_event/4,
        nil
      )
  """

  @doc """
  Executes a function within a telemetry span.

  Emits start, stop, and exception events for the given event name.
  """
  @spec span(atom(), map(), (-> result)) :: result when result: var
  def span(event, metadata, fun) when is_atom(event) and is_map(metadata) and is_function(fun, 0) do
    event_prefix = [:helmsman, event]
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        metadata
      )

      result
    rescue
      e ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: :error,
            reason: e,
            stacktrace: __STACKTRACE__
          })
        )

        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: kind,
            reason: reason,
            stacktrace: __STACKTRACE__
          })
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Emits a telemetry event.
  """
  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) when is_atom(event) do
    :telemetry.execute([:helmsman, event], measurements, metadata)
  end
end
