defmodule Glossia.Agent.Provider do
  @moduledoc """
  Behaviour for LLM provider integrations.

  Providers translate between Glossia.Agent's internal message format
  and the specific API format of each LLM service.

  ## Built-in Providers

  - `Glossia.Agent.Providers.Anthropic` - Claude models

  ## Implementing a Provider

      defmodule MyApp.Providers.Custom do
        @behaviour Glossia.Agent.Provider

        @impl true
        def chat(messages, tools, opts) do
          # Convert messages to your API format
          # Make the API call
          # Return {:ok, assistant_message}
        end

        @impl true
        def stream(messages, tools, opts) do
          Stream.resource(
            fn -> init_stream(messages, tools, opts) end,
            &receive_chunk/1,
            &cleanup/1
          )
        end

        @impl true
        def default_model, do: "my-model"
      end
  """

  alias Glossia.Agent.Message

  @type messages :: [Message.t()]
  @type tools :: [map()]
  @type opts :: keyword()

  @doc """
  Sends a chat request and returns the complete response.

  ## Options

  - `:api_key` - API key for authentication
  - `:model` - Model identifier
  - `:thinking_level` - Thinking level (:off, :minimal, :low, :medium, :high)
  - `:system` - System prompt

  Returns `{:ok, message}` with the assistant's response message,
  or `{:error, reason}` on failure.
  """
  @callback chat(messages(), tools(), opts()) ::
              {:ok, Message.t()} | {:error, term()}

  @doc """
  Sends a chat request and returns a stream of events.

  Events emitted:
  - `{:text, chunk}` - Text delta
  - `{:thinking, chunk}` - Thinking delta
  - `{:tool_call_start, id, name}` - Tool call starting
  - `{:tool_input_delta, json}` - Partial tool input
  - `{:message_complete, message}` - Final message
  - `{:error, reason}` - Error
  """
  @callback stream(messages(), tools(), opts()) :: Enumerable.t()

  @doc """
  Returns the default model for this provider.
  """
  @callback default_model() :: String.t()

  @doc """
  Validates that the provider is properly configured.
  """
  @callback validate_config(opts()) :: :ok | {:error, term()}

  @optional_callbacks [validate_config: 1]
end
