defmodule Glossia.Agent.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude provider for Glossia.Agent.

  ## Configuration

  Set your API key via:

  - Option: `api_key: "sk-ant-..."`
  - Environment: `ANTHROPIC_API_KEY`
  - Application config: `config :glossia_agent, :anthropic_api_key, "sk-ant-..."`

  ## Supported Models

  - `claude-sonnet-4-20250514` (default)
  - `claude-opus-4-20250514`
  - `claude-3-5-sonnet-20241022`
  - `claude-3-5-haiku-20241022`

  ## Extended Thinking

  Enable extended thinking for complex reasoning by setting the thinking level.
  Levels: `:off`, `:minimal`, `:low`, `:medium`, `:high`
  """

  @behaviour Glossia.Agent.Provider

  alias Glossia.Agent.Message

  @api_base "https://api.anthropic.com/v1"
  @api_version "2023-06-01"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 16384

  @impl true
  def default_model, do: @default_model

  @impl true
  def validate_config(opts) do
    case get_api_key(opts) do
      nil -> {:error, "Anthropic API key not configured"}
      _ -> :ok
    end
  end

  @impl true
  def chat(messages, tools, opts) do
    request_body = build_request(messages, tools, opts)

    case http_post("/messages", request_body, opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %{status: status, body: body}} ->
        error_message = extract_error_message(body)
        {:error, "API error (#{status}): #{error_message}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, tools, opts) do
    request_body =
      build_request(messages, tools, opts)
      |> Map.put("stream", true)

    Stream.resource(
      fn -> start_stream(request_body, opts) end,
      &receive_stream_chunk/1,
      &close_stream/1
    )
  end

  # ============================================================================
  # Request Building
  # ============================================================================

  defp build_request(messages, tools, opts) do
    model = opts[:model] || @default_model
    max_tokens = opts[:max_tokens] || @default_max_tokens

    request = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "messages" => format_messages(messages)
    }

    request
    |> maybe_add_system(opts)
    |> maybe_add_tools(tools)
    |> maybe_add_thinking(opts)
  end

  defp format_messages(messages) do
    messages
    |> Enum.map(&format_message/1)
    |> merge_consecutive_roles()
  end

  defp merge_consecutive_roles(messages) do
    # Anthropic requires alternating user/assistant roles
    # Merge consecutive messages of the same role
    messages
    |> Enum.chunk_by(& &1["role"])
    |> Enum.map(fn chunk ->
      role = hd(chunk)["role"]
      contents = Enum.flat_map(chunk, &List.wrap(&1["content"]))

      %{"role" => role, "content" => contents}
    end)
  end

  defp maybe_add_system(request, opts) do
    case opts[:system] do
      nil -> request
      system -> Map.put(request, "system", system)
    end
  end

  defp maybe_add_tools(request, []), do: request

  defp maybe_add_tools(request, tools) do
    formatted_tools =
      Enum.map(tools, fn tool ->
        %{
          "name" => tool.name,
          "description" => tool.description,
          "input_schema" => tool.parameters
        }
      end)

    Map.put(request, "tools", formatted_tools)
  end

  defp maybe_add_thinking(request, opts) do
    case opts[:thinking_level] do
      nil ->
        request

      :off ->
        request

      level when level in [:minimal, :low, :medium, :high] ->
        budget = thinking_budget(level)
        Map.put(request, "thinking", %{"type" => "enabled", "budget_tokens" => budget})
    end
  end

  defp thinking_budget(:minimal), do: 1024
  defp thinking_budget(:low), do: 2000
  defp thinking_budget(:medium), do: 8000
  defp thinking_budget(:high), do: 32000

  defp format_message(%Message{role: :user, content: content, images: []}) when is_binary(content) do
    %{"role" => "user", "content" => content}
  end

  defp format_message(%Message{role: :user, content: content, images: images}) when is_binary(content) do
    image_blocks =
      Enum.map(images, fn image ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => image.media_type,
            "data" => image.data
          }
        }
      end)

    text_block = %{"type" => "text", "text" => content}

    %{"role" => "user", "content" => image_blocks ++ [text_block]}
  end

  defp format_message(%Message{role: :assistant, content: content}) when is_binary(content) do
    %{"role" => "assistant", "content" => content}
  end

  defp format_message(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    %{
      "role" => "assistant",
      "content" => Enum.map(blocks, &format_content_block/1)
    }
  end

  defp format_message(%Message{role: :tool_result, tool_call_id: id, content: content}) do
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => id,
          "content" => encode_result(content)
        }
      ]
    }
  end

  defp format_content_block({:text, text}) do
    %{"type" => "text", "text" => text}
  end

  defp format_content_block({:tool_call, id, name, input}) do
    %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
  end

  defp format_content_block({:thinking, text}) do
    %{"type" => "thinking", "thinking" => text}
  end

  defp encode_result(%{type: :image} = image) do
    [
      %{
        "type" => "image",
        "source" => %{
          "type" => "base64",
          "media_type" => image.media_type,
          "data" => image.data
        }
      }
    ]
  end

  defp encode_result({:error, reason}) when is_binary(reason), do: "Error: #{reason}"
  defp encode_result({:error, reason}), do: "Error: #{inspect(reason)}"
  defp encode_result(result) when is_binary(result), do: result
  defp encode_result(result), do: JSON.encode!(result)

  # ============================================================================
  # Response Parsing
  # ============================================================================

  defp parse_response(%{"content" => content}) do
    blocks = Enum.map(content, &parse_content_block/1)
    Message.assistant(blocks)
  end

  defp parse_content_block(%{"type" => "text", "text" => text}) do
    {:text, text}
  end

  defp parse_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    {:tool_call, id, name, input}
  end

  defp parse_content_block(%{"type" => "thinking", "thinking" => text}) do
    {:thinking, text}
  end

  defp extract_error_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(body), do: inspect(body)

  # ============================================================================
  # Streaming
  # ============================================================================

  defp start_stream(request_body, opts) do
    url = "#{@api_base}/messages"
    headers = build_headers(opts)

    case Req.post(url,
           json: request_body,
           headers: headers,
           into: :self,
           receive_timeout: 300_000
         ) do
      {:ok, %Req.Response{status: 200} = resp} ->
        {:streaming, resp, [], nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "API error (#{status}): #{extract_error_message(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_stream_chunk({:error, _} = error) do
    {:halt, error}
  end

  defp receive_stream_chunk({:streaming, resp, content_blocks, current_tool}) do
    receive do
      {_ref, {:data, data}} ->
        {events, content_blocks, current_tool} =
          parse_sse_events(data, content_blocks, current_tool)

        {events, {:streaming, resp, content_blocks, current_tool}}

      {_ref, :done} ->
        # Emit final message
        message = Message.assistant(content_blocks)
        {[{:message_complete, message}], {:done, message}}

      {_ref, {:error, reason}} ->
        {[{:error, reason}], {:error, reason}}
    after
      300_000 ->
        {[{:error, :timeout}], {:error, :timeout}}
    end
  end

  defp receive_stream_chunk({:done, _message}) do
    {:halt, :done}
  end

  defp close_stream(:done), do: :ok
  defp close_stream({:done, _}), do: :ok
  defp close_stream({:error, _}), do: :ok
  defp close_stream({:streaming, _resp, _, _}), do: :ok

  defp parse_sse_events(data, content_blocks, current_tool) do
    data
    |> String.split("\n\n")
    |> Enum.reduce({[], content_blocks, current_tool}, fn event, {events, blocks, tool} ->
      case parse_sse_event(event) do
        nil ->
          {events, blocks, tool}

        {:content_block_start, block} ->
          tool = if match?({:tool_call, _, _, _}, block), do: block, else: tool
          {events, blocks ++ [block], tool}

        {:text_delta, text} ->
          blocks = update_last_text_block(blocks, text)
          {events ++ [{:text, text}], blocks, tool}

        {:thinking_delta, text} ->
          blocks = update_last_thinking_block(blocks, text)
          {events ++ [{:thinking, text}], blocks, tool}

        {:tool_input_delta, json} ->
          blocks = update_last_tool_input(blocks, json)
          {events ++ [{:tool_input_delta, json}], blocks, tool}

        :message_stop ->
          {events, blocks, tool}
      end
    end)
  end

  defp parse_sse_event(""), do: nil

  defp parse_sse_event(event) do
    case Regex.run(~r/data: (.+)/, event) do
      [_, json] ->
        case JSON.decode(json) do
          {:ok, data} -> parse_stream_data(data)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_stream_data(%{"type" => "content_block_start", "content_block" => block}) do
    case block do
      %{"type" => "text", "text" => text} ->
        {:content_block_start, {:text, text}}

      %{"type" => "thinking", "thinking" => text} ->
        {:content_block_start, {:thinking, text}}

      %{"type" => "tool_use", "id" => id, "name" => name} ->
        {:content_block_start, {:tool_call, id, name, %{}}}

      _ ->
        nil
    end
  end

  defp parse_stream_data(%{"type" => "content_block_delta", "delta" => delta}) do
    case delta do
      %{"type" => "text_delta", "text" => text} -> {:text_delta, text}
      %{"type" => "thinking_delta", "thinking" => text} -> {:thinking_delta, text}
      %{"type" => "input_json_delta", "partial_json" => json} -> {:tool_input_delta, json}
      _ -> nil
    end
  end

  defp parse_stream_data(%{"type" => "message_stop"}), do: :message_stop
  defp parse_stream_data(_), do: nil

  defp update_last_text_block(blocks, text) do
    case List.last(blocks) do
      {:text, existing} ->
        List.replace_at(blocks, -1, {:text, existing <> text})

      _ ->
        blocks ++ [{:text, text}]
    end
  end

  defp update_last_thinking_block(blocks, text) do
    case List.last(blocks) do
      {:thinking, existing} ->
        List.replace_at(blocks, -1, {:thinking, existing <> text})

      _ ->
        blocks ++ [{:thinking, text}]
    end
  end

  defp update_last_tool_input(blocks, json_chunk) do
    # Find the last tool_call and accumulate JSON
    idx = Enum.find_index(Enum.reverse(blocks), &match?({:tool_call, _, _, _}, &1))

    if idx do
      real_idx = length(blocks) - 1 - idx
      {:tool_call, id, name, input} = Enum.at(blocks, real_idx)

      # Accumulate JSON string, parse at the end
      new_input =
        case input do
          %{__json_buffer__: buffer} -> %{__json_buffer__: buffer <> json_chunk}
          _ -> %{__json_buffer__: json_chunk}
        end

      # Try to parse the accumulated JSON
      new_input =
        case JSON.decode(new_input[:__json_buffer__] || "") do
          {:ok, parsed} -> parsed
          _ -> new_input
        end

      List.replace_at(blocks, real_idx, {:tool_call, id, name, new_input})
    else
      blocks
    end
  end

  # ============================================================================
  # HTTP Helpers
  # ============================================================================

  defp http_post(path, body, opts) do
    url = "#{@api_base}#{path}"
    headers = build_headers(opts)

    Req.post(url, json: body, headers: headers, receive_timeout: 300_000)
  end

  defp build_headers(opts) do
    api_key = get_api_key(opts)

    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp get_api_key(opts) do
    opts[:api_key] ||
      System.get_env("ANTHROPIC_API_KEY") ||
      Application.get_env(:glossia_agent, :anthropic_api_key)
  end
end
