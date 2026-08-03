defmodule AgenticRealms.World.NPCChat.SystemPromptTest do
  @moduledoc """
  Unit tests for the chat system prompt (feature 010).

  Verifies every clause of FR-008 (a–f) appears in the rendered prompt
  via substring assertions, plus the empty-lore fallback (FR-013).

  See `specs/010-npc-conversations/contracts/system_prompt.md`.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCChat.SystemPrompt

  defp base_snapshot(overrides \\ %{}) do
    Map.merge(
      %{
        npc_name: "Garrick the Innkeeper",
        lore: "A former bridge-guard from Riverford.",
        room_name: "Stone Atrium",
        room_description: "A cool stone hall.",
        other_players: [],
        objects: [],
        player_name: "Alice"
      },
      overrides
    )
  end

  describe "text/1" do
    test "names the NPC in the opening line (FR-008a)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "You are Garrick the Innkeeper"
    end

    test "includes the lore content (FR-008a)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "A former bridge-guard from Riverford."
    end

    test "rule against meta-references is present (FR-008d)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "NEVER reference being an AI"
      assert prompt =~ "as an AI"
      assert prompt =~ "as a language model"
    end

    test "rule against reciting lore on demand is present (FR-008e)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ ~r/do not recite, paraphrase/i
      assert prompt =~ "what's your lore"
    end

    test "rule for in-theme refusal is present and prefers emote (FR-008c, FR-021)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "in-theme refusal"
      assert prompt =~ "Prefer an `emote` reply"
    end

    test "rule for structured speech-or-emote output is present (FR-008f, FR-021)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "exactly one tool call"
      assert prompt =~ "`say`"
      assert prompt =~ "`emote`"
      assert prompt =~ "NEVER mix both"
    end

    test "room name and description appear in 'The scene' section" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "Stone Atrium"
      assert prompt =~ "A cool stone hall."
    end

    test "the chatting player's name appears in the scene" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "Alice is speaking with you here."
    end

    test "with no other_players, 'Also present' line is omitted" do
      prompt = SystemPrompt.text(base_snapshot())
      refute prompt =~ "Also present"
    end

    test "with no objects, 'Nearby you can see' line is omitted" do
      prompt = SystemPrompt.text(base_snapshot())
      refute prompt =~ "Nearby you can see"
    end

    test "with empty lore, the fallback paragraph is used and the lore section heading does not contain stray empty content" do
      prompt = SystemPrompt.text(base_snapshot(%{lore: ""}))
      assert prompt =~ "You have no detailed backstory of your own"
      refute prompt =~ "# Your identity and background\n\n#"
    end

    test "is pure (idempotent for same input)" do
      snap = base_snapshot()
      assert SystemPrompt.text(snap) == SystemPrompt.text(snap)
    end

    test "with two other_players, both names appear" do
      prompt = SystemPrompt.text(base_snapshot(%{other_players: ["Bob", "Carol"]}))
      assert prompt =~ "Also present: Bob, Carol."
    end

    test "with three objects, all three short descriptions appear" do
      prompt =
        SystemPrompt.text(
          base_snapshot(%{
            objects: [
              %{name: "stone basin", short_description: "a worn stone basin"},
              %{name: "iron key", short_description: "a small iron key"},
              %{name: "oil lamp", short_description: "a sputtering oil lamp"}
            ]
          })
        )

      assert prompt =~ "stone basin (a worn stone basin)"
      assert prompt =~ "iron key (a small iron key)"
      assert prompt =~ "oil lamp (a sputtering oil lamp)"
    end

    test "out-of-scope refusal rule contains both 'in-theme refusal' and 'emote' (US4)" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "in-theme refusal"
      assert prompt =~ "Prefer an `emote` reply"
    end

    test "system prompt includes a conversational-memory rule that distinguishes lore-dump from follow-up questions" do
      prompt = SystemPrompt.text(base_snapshot())
      assert prompt =~ "CONVERSATIONAL MEMORY"

      assert prompt =~ "remember and use what the player has just told you",
             "the system prompt must explicitly tell the LLM to remember prior turns"

      assert prompt =~ "NEVER out-of-scope" or prompt =~ "is NEVER out-of-scope",
             "the system prompt must explicitly state that conversational follow-ups are NOT out-of-scope refusals"
    end

    test "system prompt instructs the LLM to treat player-supplied facts as true" do
      prompt = SystemPrompt.text(base_snapshot())

      assert prompt =~ "first-person claims by the player as TRUE",
             "the system prompt must tell the LLM that player-supplied facts are accepted as-is"

      assert prompt =~ "do NOT need outside facts" or prompt =~ "you do NOT need outside facts",
             "the system prompt must tell the LLM not to require external verification"

      assert prompt =~ "today is my birthday",
             "the prompt should include the birthday example as a concrete few-shot"
    end
  end
end
