# Contract: NPC system-prompt quest context

The NPC's per-turn system prompt is assembled in `AgenticRealms.World.NPCChat.SystemPrompt` (`lib/agenticrealms/world/npc_chat/system_prompt.ex`) from `AgenticRealms.World.NPCChat.Context`. This contract specifies the new quest section that's added to that prompt.

## Context computation

`AgenticRealms.World.NPCChat.Context` gains a `quest_context/2` function:

```elixir
@spec quest_context(viewer_player_id :: integer, npc_blueprint_id :: string) :: map
def quest_context(viewer_player_id, npc_blueprint_id) do
  blueprint = Repo.get!(NPCBlueprint, npc_blueprint_id)

  completed_slugs =
    QuestInstance
    |> where([q], q.player_id == ^viewer_player_id and q.npc_blueprint_id == ^npc_blueprint_id and q.state == "completed")
    |> select([q], q.slug)
    |> Repo.all()

  active_instances =
    QuestInstance
    |> where([q], q.player_id == ^viewer_player_id and q.npc_blueprint_id == ^npc_blueprint_id and q.state == "active")
    |> Repo.all()
    |> Enum.map(fn inst ->
      %{
        quest_id: inst.id,
        slug: inst.slug,
        title: inst.definition_snapshot["title"],
        progress: Quests.progress_for(inst)
      }
    end)

  offerable_quests =
    blueprint.quests
    |> Enum.reject(fn q -> q["slug"] in completed_slugs end)
    |> Enum.reject(fn q -> Enum.any?(active_instances, &(&1.slug == q["slug"])) end)
    |> Enum.map(fn q ->
      %{
        slug: q["slug"],
        title: q["title"],
        narrative: q["narrative"],
        criteria_summary: criteria_summary(q["criteria"])
      }
    end)

  %{
    offerable_quests: offerable_quests,
    active_instances: active_instances,
    completed_slugs: completed_slugs
  }
end
```

`criteria_summary/1` produces a short natural-language summary of each criterion (e.g. `"Bring 3 golden apples"`) suitable for inclusion in a system prompt without overwhelming token count.

## System-prompt rendering

`SystemPrompt.render/1` is extended to include a `## Quests` section when the quest context contains any non-empty list:

```text
## Quests

You can offer the following quests to this player:

- Slug: `golden_apples` — "The Orchard Keeper's Errand"
  Narrative: "Three golden apples have rolled away..."
  Objective: Bring 3 golden apples.

This player has these quests open with you right now (use these quest_ids when calling check_progress or finalize_quest):

- quest_id: `<uuid>` — slug `golden_apples` — "The Orchard Keeper's Errand"
  Progress: Golden Apples: 1 / 3

This player has already completed these quests with you (react in character if they ask again; do NOT offer them):

- `another_slug`

When the player expresses clear intent to accept one of your offerable quests in natural language, call the accept_quest tool with that quest's slug. When they ask how they're doing on an active quest, call check_progress with the relevant quest_id. When they express clear intent to turn in a quest, call finalize_quest with that quest_id. All three tools may return a structured failure ({"ok": false, "reason": ..., "details": ...}); render any failure in character.
```

The exact prose is illustrative; the rendering function should produce equivalent content. When `offerable_quests`, `active_instances`, AND `completed_slugs` are all empty, the entire `## Quests` section is omitted (to avoid wasted tokens on NPCs with no quest catalog and no quest history with this player).

## Behaviour when blueprint has no catalog

If `blueprint.quests == []` AND there are no active instances AND no completed slugs for this player with this NPC → omit the entire `## Quests` section. This is the dominant case for any pre-existing NPC blueprints (whose `quests` defaults to `[]` per the migration).

## Tests (`test/agenticrealms/world/npc_chat/context_quest_test.exs`)

- Empty blueprint catalog + no history → `quest_context/2` returns `%{offerable_quests: [], active_instances: [], completed_slugs: []}`; system prompt omits the section.
- Blueprint with 1 quest + no history → `offerable_quests` lists it; `active_instances` and `completed_slugs` empty.
- Blueprint with 1 quest + 1 active instance from the same slug → `offerable_quests` excludes the slug (no double-offer); `active_instances` lists the open quest with current per-criterion progress.
- Blueprint with 1 quest + 1 completed → `offerable_quests` excludes the slug; `completed_slugs` lists it.
- Progress numbers in `active_instances` reflect current inventory (verified via fixture inventory).
- `criteria_summary/1` produces concise per-criterion strings.
