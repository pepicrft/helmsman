defmodule Helmsman.Providers.Ollama do
  @moduledoc """
  Ollama provider – self-hosted OpenAI-compatible Chat Completions API.

  ## Implementation

  Uses built-in OpenAI-style encoding/decoding defaults.
  Ollama exposes an OpenAI-compatible API at `/v1`, so no custom
  request/response handling is needed.

  ## Self-Hosted Configuration

  Ollama is a self-hosted inference server. Users must:

  1. Install and run Ollama (https://ollama.com)
  2. Pull a model (e.g., `ollama pull llama3.2`)
  3. Optionally set a custom `base_url` if not running on localhost

  ## Authentication

  Ollama does not require authentication by default.
  Set `OLLAMA_API_KEY` to any non-empty value (it is required by the
  provider interface but not validated by Ollama).

  ## Configuration

      # Add to .env file (automatically loaded)
      OLLAMA_API_KEY=ollama

  ## Examples

      # Basic usage with default localhost
      Helmsman.run(agent, "Hello!",
        model: "ollama:llama3.2"
      )

      # With custom base_url for a remote Ollama instance
      MyAgent.start_link(
        model: "ollama:llama3.2",
        base_url: "http://my-server:11434/v1"
      )
  """

  use ReqLLM.Provider,
    id: :ollama,
    default_base_url: "http://localhost:11434/v1",
    default_env_key: "OLLAMA_API_KEY"

  use ReqLLM.Provider.Defaults

  @provider_schema []
end
