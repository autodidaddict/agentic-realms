defmodule AgenticRealms.World.IntentResolver.Tools do
  @moduledoc """
  Tool definitions sent to the Anthropic Messages API on every intent-resolver
  request. One tool per canonical game action plus `refuse` — the model's only
  sanctioned non-action output.

  `list/0` returns the tool array in wire format (a list of maps that Jason
  serializes directly). The `cache_control` marker is placed on the system
  block (see `IntentResolver`), NOT here — render order is tools → system →
  messages, so a marker on the system block caches both the tools array and
  the system prompt as one window.

  Note on caching: Haiku 4.5's minimum cacheable prefix is 4096 tokens. The
  system prompt + tools here total well under that, so the cache marker is
  effectively a no-op at the current prompt size (it produces no error — the
  request just isn't cached). It is kept so caching engages automatically if
  the prompt later grows past the threshold. Per-request cost without caching
  is negligible at Haiku rates.

  See `specs/005-llm-intent-parser/contracts/tools.md`.
  """

  @doc "Set of recognized tool names (the 9 canonical actions + `refuse`)."
  @spec names() :: MapSet.t(String.t())
  def names do
    MapSet.new(~w(take drop move look inventory say emote tell whisper chat refuse))
  end

  @doc "The tool definitions, in wire order, for the Anthropic `tools` field."
  @spec list() :: [map()]
  def list do
    [
      tool(
        "take",
        "Pick up an object that is currently in the player's room and move it into their inventory. Use this when the player wants to acquire, grab, pick up, fetch, take, or otherwise possess an object visible in the current room.",
        %{
          "type" => "object",
          "properties" => %{
            "object" => %{
              "type" => "string",
              "description" =>
                "The name of the object to take, as the player referred to it (e.g. 'brass lantern', 'lantern'). Case-insensitive."
            }
          },
          "required" => ["object"]
        }
      ),
      tool(
        "drop",
        "Drop an object from the player's inventory into the current room. Use this when the player wants to put down, release, let go of, or otherwise relinquish an object they are carrying.",
        %{
          "type" => "object",
          "properties" => %{
            "object" => %{
              "type" => "string",
              "description" =>
                "The name of the object to drop (must be in the player's inventory). Case-insensitive."
            }
          },
          "required" => ["object"]
        }
      ),
      tool(
        "move",
        "Move the player through an exit in the current room. Use this when the player wants to go, walk, head, travel, or otherwise change rooms in a specific direction. If the player names a target room or a non-cardinal direction, refuse instead.",
        %{
          "type" => "object",
          "properties" => %{
            "direction" => %{
              "type" => "string",
              "enum" => ["north", "south", "east", "west", "up", "down"],
              "description" => "One of the six canonical directions."
            }
          },
          "required" => ["direction"]
        }
      ),
      tool(
        "look",
        "Render the player's current room (no target) OR examine a specific object, player, or NPC currently in the room (target). Use no target to show the room as a whole — its name, description, exits, objects visible, other players present, and any NPCs in the 'Also here' section. Pass a `target` to show the detail (long description) of a single object, player, or NPC. Examine, inspect, study, read, look-at, take-a-closer-look-at — all of these map to this tool with a `target`.",
        %{
          "type" => "object",
          "properties" => %{
            "target" => %{
              "type" => "string",
              "description" =>
                "Optional. The name of a specific object, player, or NPC to examine, as the player referred to it (e.g. 'brass lantern', 'lantern', 'alice', 'me', 'garrick', 'the innkeeper', 'the old man'). Omit this property entirely to render the whole room. Case-insensitive — the game performs its own resolution against actual room/inventory/player/NPC contents. For self-examination ('look at me', 'examine myself'), pass the literal string 'me'."
            }
          },
          "required" => []
        }
      ),
      tool(
        "inventory",
        "List the objects the player is currently carrying. Use this when the player asks what they have, what's in their pockets, their inventory, their stuff, etc.",
        %{"type" => "object", "properties" => %{}, "required" => []}
      ),
      tool(
        "say",
        "Broadcast a spoken utterance to every player currently in the same room as the speaker. Use this when the player wants to speak aloud, talk, say something out loud, or address everyone in the room.",
        %{
          "type" => "object",
          "properties" => %{
            "text" => %{
              "type" => "string",
              "description" =>
                "The exact text the player wants to speak. Preserve their casing and punctuation."
            }
          },
          "required" => ["text"]
        }
      ),
      tool(
        "emote",
        "Perform a third-person narrative action visible to everyone in the room, including the actor. Use this when the player describes an action they are taking (waving, bowing, smiling, gesturing) rather than speaking.",
        %{
          "type" => "object",
          "properties" => %{
            "text" => %{
              "type" => "string",
              "description" =>
                "The action verb phrase, third-person present-tense without the actor's name (e.g. 'waves at the fire', 'bows deeply')."
            }
          },
          "required" => ["text"]
        }
      ),
      tool(
        "tell",
        "Send a private message to a named player who can be anywhere in the world (any room, online). Use this when the player wants to message, contact, DM, send a note to, or tell a specific named player something. Cross-room delivery is fine.",
        %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "The recipient's character name. Case-insensitive."
            },
            "text" => %{"type" => "string", "description" => "The private message text."}
          },
          "required" => ["recipient", "text"]
        }
      ),
      tool(
        "whisper",
        "Send a private message to a named player who is in the SAME room as the speaker. Use this when the player wants to whisper, mutter aside, lean in close to, or speak privately with someone nearby. If the recipient is in a different room the game refuses — use `tell` for cross-room private messages.",
        %{
          "type" => "object",
          "properties" => %{
            "recipient" => %{
              "type" => "string",
              "description" => "The recipient's display name. They must be in the same room."
            },
            "text" => %{"type" => "string", "description" => "The whispered message text."}
          },
          "required" => ["recipient", "text"]
        }
      ),
      tool(
        "chat",
        "Initiate or continue a conversation with an NPC in the player's current room. Use this when the player wants to talk to, ask, address, converse with, speak with, or otherwise chat with a named NPC. The NPC's name MUST match an NPC visible in the current room. The message is what the player is saying or asking. Examples: 'talk to garrick', 'ask the innkeeper about the rumors', 'say hello to the guard', 'tell garrick I'm new here' all map to chat. (Note: a plain `say <text>` without a target stays as the `say` tool — only chooses chat when the player is clearly addressing a specific NPC.)",
        %{
          "type" => "object",
          "properties" => %{
            "npc" => %{
              "type" => "string",
              "description" =>
                "The NPC's name as the player referred to them (e.g., 'garrick', 'the innkeeper'). Case-insensitive substring match against the NPCs visible in the room."
            },
            "message" => %{
              "type" => "string",
              "description" =>
                "What the player is saying to the NPC. Preserve casing and punctuation."
            }
          },
          "required" => ["npc", "message"]
        }
      ),
      tool(
        "refuse",
        "Decline to act on the player's input because it does not map to a supported action. Use this when: the intent is out of game scope ('what time is it?', 'save my game'); the intent is for a future action not yet supported (combat, magic, examining specific objects, reading); the intent is multi-step (only one action per turn is allowed — refuse with a hint to chain manually); the intent is too ambiguous to act on; or the input is nonsense or not in English. The `message` field is the player-facing refusal — write it brief and helpful, hinting at what the game CAN do when relevant.",
        %{
          "type" => "object",
          "properties" => %{
            "message" => %{
              "type" => "string",
              "description" =>
                "The refusal message the player sees. Brief (one or two sentences), friendly. When refusing a missing action, hint at what IS supported. Never mention the LLM, tools, or API internals."
            }
          },
          "required" => ["message"]
        }
      )
    ]
  end

  defp tool(name, description, input_schema) do
    %{"name" => name, "description" => description, "input_schema" => input_schema}
  end
end
