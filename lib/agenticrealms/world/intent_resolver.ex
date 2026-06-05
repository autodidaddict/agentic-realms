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
  alias AgenticRealms.World.IntentResolver.{ContextSnapshot, SystemPrompt, Tools, WizardTools}
  alias AgenticRealms.World.Toolsets

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
          | {:chat, String.t(), String.t()}

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

  # Feature 010 — chat verb dispatch. The NPC's name (in their current room)
  # is the `npc` field; the player's message is `message`.
  defp to_action("chat", %{"npc" => n, "message" => m})
       when is_binary(n) and n != "" and is_binary(m) and m != "" do
    {:ok, {:chat, n, m}}
  end

  defp to_action("refuse", %{"message" => m}) when is_binary(m) and m != "" do
    {:error, m}
  end

  # Recognized tool name but the input failed schema validation
  # (missing/empty required field, bad direction enum, etc.).
  defp to_action(_name, _input), do: {:error, @generic_refusal}

  # ─────────────────────────────────────────────────────────────────────
  # Feature 014 — wizard authoring resolver (`:blueprints` mode)
  # ─────────────────────────────────────────────────────────────────────

  @wizard_system_prompt """
  You are a tool-call dispatcher for a wizard authoring reusable templates
  ("blueprints") in a text-driven fantasy game. The wizard speaks a prompt
  describing the kind of thing they want to author. Your sole job is to call
  exactly one tool per turn — never produce free-form prose.

  Choose the tool by what the prompt describes:
  - A character, creature, or person (an NPC) → `draft_npc_blueprint`.
  - An inanimate object, item, or fixture → `draft_object_blueprint`.
  - A question, an edit to an existing thing, a place / room, or anything
    off-task → `refuse`.
  - To ground toolset proposals for an NPC you MAY first call `list_toolsets`
    to see the named behavior groups available, then call
    `draft_npc_blueprint` proposing only names from that list.

  `draft_object_blueprint`:
  - `name`: short lowercase noun phrase (1–4 words).
  - `short_description`: one concrete noun phrase (≤ 100 chars).
  - `long_description`: multi-sentence examine prose, grounded in the prompt —
    do not invent facts the wizard did not imply.
  - `fixed`: true only when the thing is embedded, bolted, mounted, or immobile.

  `draft_npc_blueprint`:
  - `name`: the NPC's name or short descriptor (e.g. "Garrick", "cave troll").
  - `short_description`: one-line room-listing phrase with an article.
  - `long_description`: multi-sentence examine prose.
  - `lore`: private backstory / personality grounding the NPC's conversation;
    not shown verbatim to players.
  - `fixed`: true only if the NPC cannot be moved (rare).
  - `toolsets`: names of behavior groups to attach, chosen from `list_toolsets`.
    Omit or leave empty if none fit; never invent names.
  """

  # The model may call `list_toolsets` to ground toolset proposals before it
  # drafts. Bound the number of read-tool hops so a misbehaving model can't
  # loop forever; the draft/refuse call terminates the loop.
  @max_wizard_tool_hops 3

  @doc """
  Resolve a wizard's natural-language prompt into a blueprint *draft*.
  Returns `{:ok, {:draft_blueprint, fields}}` (object),
  `{:ok, {:draft_npc_blueprint, fields}}` (npc), or
  `{:error, refusal_message}`. Never raises — failures collapse to
  refusals — and never persists anything.

  The model may call the `list_toolsets` read tool to ground NPC toolset
  proposals; the resolver answers it and continues the conversation until
  the model drafts or refuses (bounded by `@max_wizard_tool_hops`).

  Used by `GameLive` when a wizard submits the prompt textarea while in
  `:blueprints` mode (`:authoring_mode == :blueprints`).
  """
  @spec resolve_wizard_blueprint(integer(), String.t()) ::
          {:ok, {:draft_blueprint, map()}}
          | {:ok, {:draft_npc_blueprint, map()}}
          | {:error, String.t()}
  def resolve_wizard_blueprint(player_id, raw_input)
      when is_integer(player_id) and is_binary(raw_input) do
    started_at = System.monotonic_time(:millisecond)
    outcome = do_resolve_wizard_blueprint(raw_input)
    emit_wizard_telemetry(player_id, raw_input, outcome, started_at)
    outcome
  end

  defp do_resolve_wizard_blueprint(raw_input) do
    trimmed = String.trim(raw_input)

    cond do
      trimmed == "" ->
        {:error, @generic_refusal}

      String.length(trimmed) > @max_input_length ->
        {:error, @too_long_refusal}

      true ->
        run_blueprint_loop([%{"role" => "user", "content" => trimmed}], 0)
    end
  end

  # Exhausted the read-tool hop budget without a draft/refuse — treat as
  # an unparseable intent rather than looping.
  defp run_blueprint_loop(_messages, hops) when hops >= @max_wizard_tool_hops do
    {:error, @generic_refusal}
  end

  defp run_blueprint_loop(messages, hops) do
    request = build_wizard_blueprint_request(messages)

    case Anthropic.create_message(request) do
      {:ok, response} ->
        case extract_single_tool_use(response) do
          {:ok, %{"name" => "list_toolsets", "id" => id}} when is_binary(id) ->
            messages
            |> append_tool_round(id, "list_toolsets", list_toolsets_result())
            |> run_blueprint_loop(hops + 1)

          {:ok, tool_use} ->
            map_wizard_tool_use(tool_use)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :no_api_key} ->
        {:error, @no_key_refusal}

      {:error, _reason} ->
        {:error, @generic_refusal}
    end
  end

  defp build_wizard_blueprint_request(messages) when is_list(messages) do
    %{
      "max_tokens" => 512,
      "system" => [
        %{
          "type" => "text",
          "text" => @wizard_system_prompt,
          "cache_control" => %{"type" => "ephemeral"}
        }
      ],
      "tools" => WizardTools.list_blueprints(),
      "tool_choice" => %{"type" => "any"},
      "messages" => messages
    }
  end

  # Append the model's `list_toolsets` call + our tool_result so the next
  # turn sees the grounded toolset list.
  defp append_tool_round(messages, tool_use_id, name, result_text) do
    messages ++
      [
        %{
          "role" => "assistant",
          "content" => [
            %{"type" => "tool_use", "id" => tool_use_id, "name" => name, "input" => %{}}
          ]
        },
        %{
          "role" => "user",
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => tool_use_id, "content" => result_text}
          ]
        }
      ]
  end

  # The toolsets the LLM is allowed to propose for an NPC, as a readable
  # block fed back through the `list_toolsets` tool_result.
  defp list_toolsets_result do
    case Toolsets.list_for(:npc) do
      [] ->
        "No toolsets are registered. Do not propose any."

      toolsets ->
        toolsets
        |> Enum.map(fn t -> "- #{t.name}: #{t.description || "(no description)"}" end)
        |> Enum.join("\n")
    end
  end

  @doc """
  Parse an Anthropic Messages API response body into a wizard blueprint
  draft outcome (single-shot, no `list_toolsets` hop). Exposed for unit
  testing the tool-use → outcome mapping without HTTP.
  """
  @spec parse_wizard_blueprint_response(map()) ::
          {:ok, {:draft_blueprint, map()}}
          | {:ok, {:draft_npc_blueprint, map()}}
          | {:error, String.t()}
  def parse_wizard_blueprint_response(response) do
    case extract_single_tool_use(response) do
      {:ok, tool_use} -> map_wizard_tool_use(tool_use)
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_single_tool_use(%{"content" => content}) when is_list(content) do
    case Enum.filter(content, &(&1["type"] == "tool_use")) do
      [tool_use] -> {:ok, tool_use}
      [_ | _] -> {:error, @multi_step_refusal}
      [] -> {:error, @generic_refusal}
    end
  end

  defp extract_single_tool_use(_), do: {:error, @generic_refusal}

  defp map_wizard_tool_use(%{"name" => name, "input" => input}) when is_map(input) do
    if MapSet.member?(WizardTools.names_blueprints(), name) do
      to_wizard_outcome(name, input)
    else
      {:error, @generic_refusal}
    end
  end

  defp map_wizard_tool_use(_), do: {:error, @generic_refusal}

  defp to_wizard_outcome("draft_object_blueprint", input) do
    with name when is_binary(name) and name != "" <- input["name"],
         short when is_binary(short) and short != "" <- input["short_description"],
         long when is_binary(long) and long != "" <- input["long_description"] do
      {:ok,
       {:draft_blueprint,
        %{
          name: name,
          short_description: short,
          long_description: long,
          fixed: input["fixed"] == true
        }}}
    else
      _ -> {:error, @generic_refusal}
    end
  end

  defp to_wizard_outcome("draft_npc_blueprint", input) do
    with name when is_binary(name) and name != "" <- input["name"],
         short when is_binary(short) and short != "" <- input["short_description"],
         long when is_binary(long) and long != "" <- input["long_description"] do
      {:ok,
       {:draft_npc_blueprint,
        %{
          name: name,
          short_description: short,
          long_description: long,
          lore: (is_binary(input["lore"]) && input["lore"]) || "",
          fixed: input["fixed"] == true,
          # FR-018 — drop any proposed name not in the NPC toolset registry
          # so a hallucinated toolset never reaches the picker/commit.
          toolsets: grounded_toolsets(input["toolsets"])
        }}}
    else
      _ -> {:error, @generic_refusal}
    end
  end

  defp to_wizard_outcome("refuse", %{"message" => m}) when is_binary(m) and m != "",
    do: {:error, m}

  defp to_wizard_outcome(_, _), do: {:error, @generic_refusal}

  defp grounded_toolsets(names) when is_list(names) do
    registered = Toolsets.list_for(:npc) |> MapSet.new(& &1.name)
    Enum.filter(names, &(is_binary(&1) and MapSet.member?(registered, &1)))
  end

  defp grounded_toolsets(_), do: []

  @wizard_world_system_prompt """
  You are a tool-call dispatcher for a wizard manifesting a one-off
  Object directly into their current room in a text-driven game. The
  wizard speaks a prompt describing a specific concrete thing they
  want to exist in the world right now. Your sole job is to call
  exactly one tool — either `manifest_object_freeform` (extracting
  fields) or `refuse` — and never to produce free-form prose.

  The thing being manifested is a one-off, NOT a reusable archetype.
  Use `manifest_object_freeform` for concrete particulars
  ("the small clay pot leaning against the eastern wall, half-empty");
  refuse if the prompt is a question, an edit request, or describes
  a place / NPC / quest.

  Field formatting rules:
  - `name`: short lowercase noun phrase (1–4 words), no leading article.
  - `short_description`: lowercase noun phrase WITH an indefinite
    article (e.g., "a small clay pot"), ≤ 40 chars, NO trailing
    period. This is the line shown in room listings.
  - `long_description`: multi-sentence prose for the examine view.
  - `fixed`: true only if the wizard's prompt implies the thing is
    embedded, bolted, mounted, or otherwise immobile.
  """

  @doc """
  Resolve a wizard's natural-language prompt while in `:world` mode
  into an Object draft. Returns
  `{:ok, {:freeform_object, fields_map}}` or `{:error, refusal}`.
  Mirrors `resolve_wizard_blueprint/2` but uses the world-mode tool
  set + system prompt.
  """
  @spec resolve_wizard_world(integer(), String.t()) ::
          {:ok, {:freeform_object, map()}} | {:error, String.t()}
  def resolve_wizard_world(player_id, raw_input)
      when is_integer(player_id) and is_binary(raw_input) do
    started_at = System.monotonic_time(:millisecond)
    outcome = do_resolve_wizard_world(raw_input)
    emit_wizard_world_telemetry(player_id, raw_input, outcome, started_at)
    outcome
  end

  defp do_resolve_wizard_world(raw_input) do
    trimmed = String.trim(raw_input)

    cond do
      trimmed == "" ->
        {:error, @generic_refusal}

      String.length(trimmed) > @max_input_length ->
        {:error, @too_long_refusal}

      true ->
        request = build_wizard_world_request(trimmed)

        case Anthropic.create_message(request) do
          {:ok, response} -> parse_wizard_world_response(response)
          {:error, :no_api_key} -> {:error, @no_key_refusal}
          {:error, _reason} -> {:error, @generic_refusal}
        end
    end
  end

  defp build_wizard_world_request(user_message) do
    %{
      "max_tokens" => 512,
      "system" => [
        %{
          "type" => "text",
          "text" => @wizard_world_system_prompt,
          "cache_control" => %{"type" => "ephemeral"}
        }
      ],
      "tools" => WizardTools.list_world(),
      "tool_choice" => %{"type" => "any"},
      "messages" => [%{"role" => "user", "content" => user_message}]
    }
  end

  @doc """
  Parse an Anthropic Messages API response body into a wizard
  world-mode freeform-Object outcome. Exposed for unit testing without
  HTTP.
  """
  @spec parse_wizard_world_response(map()) ::
          {:ok, {:freeform_object, map()}} | {:error, String.t()}
  def parse_wizard_world_response(%{"content" => content}) when is_list(content) do
    case Enum.filter(content, &(&1["type"] == "tool_use")) do
      [tool_use] -> map_wizard_world_tool_use(tool_use)
      [_ | _] -> {:error, @multi_step_refusal}
      [] -> {:error, @generic_refusal}
    end
  end

  def parse_wizard_world_response(_), do: {:error, @generic_refusal}

  defp map_wizard_world_tool_use(%{"name" => name, "input" => input}) when is_map(input) do
    if MapSet.member?(WizardTools.names_world(), name) do
      to_wizard_world_outcome(name, input)
    else
      {:error, @generic_refusal}
    end
  end

  defp map_wizard_world_tool_use(_), do: {:error, @generic_refusal}

  defp to_wizard_world_outcome("manifest_object_freeform", input) do
    with name when is_binary(name) and name != "" <- input["name"],
         short when is_binary(short) and short != "" <- input["short_description"],
         long when is_binary(long) and long != "" <- input["long_description"] do
      {:ok,
       {:freeform_object,
        %{
          name: name,
          short_description: short,
          long_description: long,
          fixed: input["fixed"] == true
        }}}
    else
      _ -> {:error, @generic_refusal}
    end
  end

  defp to_wizard_world_outcome("refuse", %{"message" => m}) when is_binary(m) and m != "",
    do: {:error, m}

  defp to_wizard_world_outcome(_, _), do: {:error, @generic_refusal}

  defp emit_wizard_world_telemetry(player_id, raw_input, outcome, started_at) do
    latency_ms = System.monotonic_time(:millisecond) - started_at

    {result, tool_name} =
      case outcome do
        {:ok, {:freeform_object, _}} -> {:object_chosen, "manifest_object_freeform"}
        {:error, _} -> {:refused, nil}
      end

    Logger.info(
      "intent_resolver mode=wizard_world player_id=#{player_id} " <>
        "input_length=#{byte_size(raw_input)} outcome=#{result} " <>
        "tool_name=#{tool_name || "-"} latency_ms=#{latency_ms}"
    )

    :telemetry.execute(
      [:agenticrealms, :intent_resolver, :resolve_wizard_world],
      %{latency_ms: latency_ms},
      %{player_id: player_id, outcome: result, tool_name: tool_name}
    )
  end

  defp emit_wizard_telemetry(player_id, raw_input, outcome, started_at) do
    latency_ms = System.monotonic_time(:millisecond) - started_at

    {result, tool_name} =
      case outcome do
        {:ok, {:draft_blueprint, _}} -> {:draft_chosen, "draft_object_blueprint"}
        {:ok, {:draft_npc_blueprint, _}} -> {:draft_chosen, "draft_npc_blueprint"}
        {:error, _} -> {:refused, nil}
      end

    Logger.info(
      "intent_resolver mode=wizard_blueprints player_id=#{player_id} " <>
        "input_length=#{byte_size(raw_input)} outcome=#{result} " <>
        "tool_name=#{tool_name || "-"} latency_ms=#{latency_ms}"
    )

    :telemetry.execute(
      [:agenticrealms, :intent_resolver, :resolve_wizard_blueprint],
      %{latency_ms: latency_ms},
      %{player_id: player_id, outcome: result, tool_name: tool_name}
    )
  end

  # ─────────────────────────────────────────────────────────────────────

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
