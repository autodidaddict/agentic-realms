defmodule AgenticRealms.World.NPCChat.Tools do
  @moduledoc """
  Tool definitions for the chat LLM call (feature 010).

  Two tools, `say` and `emote`. With `tool_choice: {type: "any"}` on the
  Anthropic request, the model MUST produce exactly one of them per turn
  (FR-021). This shape eliminates structured-output ambiguity.

  See `specs/010-npc-conversations/contracts/tools.md`.
  """

  @doc "The set of recognized tool names (`say`, `emote`)."
  @spec names() :: MapSet.t(String.t())
  def names, do: MapSet.new(~w(say emote))

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
      }
    ]
  end
end
