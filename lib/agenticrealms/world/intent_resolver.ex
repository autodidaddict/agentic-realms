defmodule AgenticRealms.World.IntentResolver do
  @moduledoc """
  Natural-language → canonical-action resolver (feature 005).

  When the fast `CommandParser` returns `{:unknown, raw}`, `GameLive` routes
  the input here. `resolve/2` builds a context snapshot, calls the Anthropic
  Messages API with tool use, and maps the single `tool_use` block to a
  canonical action tuple — shape-compatible with the `CommandParser`
  sentinels so `GameLive` can dispatch it through the same handlers.

  Every failure mode (missing API key, HTTP error, timeout, malformed
  response, unrecognized tool, multiple tool calls) collapses to a graceful
  `{:error, refusal_message}`. No exception escapes `resolve/2`.

  See `specs/005-llm-intent-parser/contracts/intent_resolver_api.md`.
  """

  require Logger

  alias AgenticRealms.Anthropic
  alias AgenticRealms.World.IntentResolver.{ContextSnapshot, SystemPrompt, Tools}

  @max_input_length 500
  @max_tokens 256

  @generic_refusal "I'm not sure what you meant just now."
  @multi_step_refusal "Try one action at a time."
  @no_room_refusal "You are nowhere."
  @too_long_refusal "Your message is too long (max 500 characters)."
  # Mirrors the pre-005 unknown-command copy — used when no API key is set so
  # the feature degrades gracefully instead of crashing.
  @no_key_refusal "I don't understand that."

  @type action_tuple ::
          {:take, String.t()}
          | {:drop, String.t()}
          | {:move, atom()}
          | {:look}
          | {:look, String.t()}
          | {:inventory}
          | {:say, String.t()}
          | {:emote, String.t()}
          | {:tell, String.t(), String.t()}
          | {:whisper, String.t(), String.t()}

  @doc """
  Resolve `raw_input` for `player_id` into a canonical action or a refusal.

  Returns `{:ok, action_tuple}` or `{:error, refusal_message}`. Always
  succeeds in the sense of never raising — failures become refusals.
  """
  @spec resolve(integer(), String.t()) :: {:ok, action_tuple()} | {:error, String.t()}
  def resolve(player_id, raw_input) when is_integer(player_id) and is_binary(raw_input) do
    started_at = System.monotonic_time(:millisecond)
    outcome = do_resolve(player_id, raw_input)
    emit_telemetry(player_id, raw_input, outcome, started_at)
    outcome
  end

  defp do_resolve(player_id, raw_input) do
    trimmed = String.trim(raw_input)

    cond do
      trimmed == "" ->
        {:error, @generic_refusal}

      String.length(trimmed) > @max_input_length ->
        {:error, @too_long_refusal}

      true ->
        case ContextSnapshot.build(player_id, trimmed) do
          {:ok, user_message} -> call_and_parse(user_message)
          {:error, :no_current_room} -> {:error, @no_room_refusal}
        end
    end
  end

  defp call_and_parse(user_message) do
    request = build_request(user_message)

    case Anthropic.create_message(request) do
      {:ok, response} -> parse_response(response)
      {:error, :no_api_key} -> {:error, @no_key_refusal}
      {:error, _reason} -> {:error, @generic_refusal}
    end
  end

  defp build_request(user_message) do
    %{
      "max_tokens" => @max_tokens,
      "system" => [
        %{
          "type" => "text",
          "text" => SystemPrompt.text(),
          # Marker on the system block caches tools + system together
          # (render order is tools → system → messages).
          "cache_control" => %{"type" => "ephemeral"}
        }
      ],
      "tools" => Tools.list(),
      # `any` forces a tool call; no `disable_parallel_tool_use` so the model
      # can — and per the system prompt should — pick `refuse` for multi-step
      # intent rather than silently collapsing to one action.
      "tool_choice" => %{"type" => "any"},
      "messages" => [%{"role" => "user", "content" => user_message}]
    }
  end

  @doc """
  Parse an Anthropic Messages API response body into a resolver outcome.

  Scans `content` for `tool_use` blocks: exactly one recognized block maps to
  an action tuple (or, for `refuse`, to `{:error, message}`); multiple blocks
  → multi-step refusal; anything else → generic refusal. Exposed for unit
  testing the tool-use → action mapping without DB or HTTP.
  """
  @spec parse_response(map()) :: {:ok, action_tuple()} | {:error, String.t()}
  def parse_response(%{"content" => content}) when is_list(content) do
    case Enum.filter(content, &(&1["type"] == "tool_use")) do
      [tool_use] -> map_tool_use(tool_use)
      [_ | _] -> {:error, @multi_step_refusal}
      [] -> {:error, @generic_refusal}
    end
  end

  def parse_response(_), do: {:error, @generic_refusal}

  defp map_tool_use(%{"name" => name, "input" => input}) when is_map(input) do
    if MapSet.member?(Tools.names(), name) do
      to_action(name, input)
    else
      {:error, @generic_refusal}
    end
  end

  defp map_tool_use(_), do: {:error, @generic_refusal}

  defp to_action("take", %{"object" => o}) when is_binary(o) and o != "", do: {:ok, {:take, o}}
  defp to_action("drop", %{"object" => o}) when is_binary(o) and o != "", do: {:ok, {:drop, o}}

  defp to_action("look", %{"target" => t}) when is_binary(t) and t != "",
    do: {:ok, {:look, t}}

  defp to_action("look", _), do: {:ok, {:look}}
  defp to_action("inventory", _), do: {:ok, {:inventory}}
  defp to_action("say", %{"text" => t}) when is_binary(t) and t != "", do: {:ok, {:say, t}}
  defp to_action("emote", %{"text" => t}) when is_binary(t) and t != "", do: {:ok, {:emote, t}}

  # Literal clauses so the direction atoms are guaranteed to exist — never
  # String.to_atom/to_existing_atom on model-supplied input.
  defp to_action("move", %{"direction" => "north"}), do: {:ok, {:move, :north}}
  defp to_action("move", %{"direction" => "south"}), do: {:ok, {:move, :south}}
  defp to_action("move", %{"direction" => "east"}), do: {:ok, {:move, :east}}
  defp to_action("move", %{"direction" => "west"}), do: {:ok, {:move, :west}}
  defp to_action("move", %{"direction" => "up"}), do: {:ok, {:move, :up}}
  defp to_action("move", %{"direction" => "down"}), do: {:ok, {:move, :down}}

  defp to_action("tell", %{"recipient" => r, "text" => t})
       when is_binary(r) and r != "" and is_binary(t) and t != "" do
    {:ok, {:tell, r, t}}
  end

  defp to_action("whisper", %{"recipient" => r, "text" => t})
       when is_binary(r) and r != "" and is_binary(t) and t != "" do
    {:ok, {:whisper, r, t}}
  end

  defp to_action("refuse", %{"message" => m}) when is_binary(m) and m != "" do
    {:error, m}
  end

  # Recognized tool name but the input failed schema validation
  # (missing/empty required field, bad direction enum, etc.).
  defp to_action(_name, _input), do: {:error, @generic_refusal}

  defp emit_telemetry(player_id, raw_input, outcome, started_at) do
    latency_ms = System.monotonic_time(:millisecond) - started_at

    {result, tool_name} =
      case outcome do
        {:ok, action} -> {:action_chosen, action |> elem(0) |> Atom.to_string()}
        {:error, _} -> {:refused, nil}
      end

    Logger.info(
      "intent_resolver player_id=#{player_id} input_length=#{byte_size(raw_input)} " <>
        "outcome=#{result} tool_name=#{tool_name || "-"} latency_ms=#{latency_ms}"
    )

    :telemetry.execute(
      [:agenticrealms, :intent_resolver, :resolve],
      %{latency_ms: latency_ms},
      %{player_id: player_id, outcome: result, tool_name: tool_name}
    )
  end
end
