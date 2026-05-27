defmodule AgenticRealms.World.NPCChat.Tools do
  @moduledoc """
  Tool definitions for the chat LLM call (feature 010).

  Two tools, `say` and `emote`. With `tool_choice: {type: "any"}` on the
  Anthropic request, the model MUST produce exactly one of them per turn
  (FR-021). This shape eliminates structured-output ambiguity.

  See `specs/010-npc-conversations/contracts/tools.md`.
  """

  @doc """
  The set of recognized tool names.

  Feature 013 adds `accept_quest` as a third tool. `check_progress` and
  `finalize_quest` are deferred to US2/US3 in the implementation plan.
  """
  @spec names() :: MapSet.t(String.t())
  def names, do: MapSet.new(~w(say emote accept_quest check_progress finalize_quest))

  @doc "Tool definitions in wire format for the Anthropic `tools` field."
  @spec list() :: [map()]
  def list do
    [
      %{
        "name" => "say",
        "description" =>
          "Speak a quoted utterance to the player. Use this when the NPC has " <>
            "something to say in words. The text will be rendered as the NPC " <>
            "speaking the words aloud.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "text" => %{
              "type" => "string",
              "description" =>
                "The exact words the NPC speaks. One to three short sentences. " <>
                  "No surrounding quotes — they will be added at render time. " <>
                  "No third-person narration about yourself; use the `emote` tool " <>
                  "for body language."
            }
          },
          "required" => ["text"]
        }
      },
      %{
        "name" => "emote",
        "description" =>
          "Perform a non-verbal gesture, body-language reaction, or facial " <>
            "expression. Prefer this for in-theme refusals (raising an eyebrow, " <>
            "looking puzzled, shrugging) and for moments where speech isn't " <>
            "the right response. The text will be rendered as third-person " <>
            "narration attributed to the NPC by name.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "text" => %{
              "type" => "string",
              "description" =>
                "A short third-person narration of the NPC's action, written " <>
                  "as a complete phrase or clause that follows the NPC's name. " <>
                  "Examples: 'raises an eyebrow curiously', 'shrugs noncommittally " <>
                  "and looks at the floor', 'frowns and rubs a callused thumb " <>
                  "across the tankard'. Do NOT include the NPC's name — it will " <>
                  "be prepended at render time."
            }
          },
          "required" => ["text"]
        }
      },
      # Feature 013 — quest acceptance. Only available when the player
      # has expressed clear intent to take on a quest from your catalog
      # (see the # Quests section of the system prompt). The slug must
      # be one of the slugs listed in your offerable_quests.
      %{
        "name" => "accept_quest",
        "description" =>
          "Record that this player has formally accepted a quest from your " <>
            "catalog. Call this when the player expresses clear acceptance " <>
            "intent in natural language (\"yes\", \"sure, I'll help\", \"I'll " <>
            "do it\"). The player will see the quest appear in their quest " <>
            "log and the required items will appear in the designated rooms.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "slug" => %{
              "type" => "string",
              "description" =>
                "The slug of the quest from your catalog (provided to you " <>
                  "in your system prompt under 'offerable quests')."
            }
          },
          "required" => ["slug"]
        }
      },
      %{
        "name" => "check_progress",
        "description" =>
          "Look up the player's current progress on one of their active " <>
            "quests with you. Read-only. Call this when the player asks " <>
            "how they're doing or whether they're ready to turn it in.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "quest_id" => %{
              "type" => "string",
              "description" =>
                "The quest_id of an active quest instance (provided to you " <>
                  "in your system prompt under 'this player's active quests')."
            }
          },
          "required" => ["quest_id"]
        }
      },
      %{
        "name" => "finalize_quest",
        "description" =>
          "Complete the quest: take the required items from the player and " <>
            "give them the reward. Atomic — if the player is missing any " <>
            "required items you'll get back a structured failure listing " <>
            "what's missing and no state changes occur. Call this when the " <>
            "player expresses clear turn-in intent.",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "quest_id" => %{
              "type" => "string",
              "description" =>
                "The quest_id of an active quest instance (provided to you " <>
                  "in your system prompt under 'this player's active quests')."
            }
          },
          "required" => ["quest_id"]
        }
      }
    ]
  end
end
