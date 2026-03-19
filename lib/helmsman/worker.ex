defmodule Helmsman.Worker do
  @moduledoc """
  Types for packaging a Helmsman worker that runs sessions in another environment.

  A worker is the deployable unit that a runtime provider boots remotely. The
  worker owns the actual `Helmsman.Session`; callers talk to it through a
  `Helmsman.SessionTransport`.
  """

  defmodule SessionSpec do
    @moduledoc """
    Serializable description of a worker-side Helmsman session.
    """

    @type t :: %__MODULE__{
            agent_module: module() | nil,
            model: String.t() | nil,
            thinking_level: Helmsman.thinking_level() | nil,
            system_prompt: String.t() | nil,
            tools: [Helmsman.tool_spec()],
            cwd: String.t() | nil,
            runtime_provider: Helmsman.runtime_provider_spec() | nil,
            session_store: Helmsman.session_store_spec() | nil,
            messages: [Helmsman.Message.t()],
            metadata: map()
          }

    defstruct [
      :agent_module,
      :model,
      :thinking_level,
      :system_prompt,
      :cwd,
      :runtime_provider,
      :session_store,
      tools: [],
      messages: [],
      metadata: %{}
    ]
  end

  defmodule Spec do
    @moduledoc """
    Serializable description of how to boot a Helmsman worker in a runtime.
    """

    @type t :: %__MODULE__{
            id: String.t() | nil,
            release: String.t() | nil,
            command: [String.t()],
            env: %{optional(String.t()) => String.t()},
            workspace_path: String.t() | nil,
            session_transport: Helmsman.SessionTransport.spec() | nil,
            metadata: map()
          }

    defstruct [
      :id,
      :release,
      :workspace_path,
      :session_transport,
      command: [],
      env: %{},
      metadata: %{}
    ]
  end
end
