# Contract: Player Identity

**Feature**: 021-character-creation

FR-014 makes the character name the player's public identity everywhere; FR-015 keeps the account
username private. This file enumerates every seam, so the rename is a checklist rather than a
search.

---

## The single lookup

```elixir
defmodule AgenticRealms.World.PlayerNames do
  @spec get(integer()) :: String.t() | nil
  @spec get_many([integer()]) :: %{integer() => String.t()}
  @spec find_by_name(String.t()) :: integer() | nil
end
```

Reads `player_state.character_name`. `get/1` returning `nil` means "this player has no character
yet", which is exactly what `GameLive.mount/3` branches on. `find_by_name/1` is case-insensitive
and uses the `lower(character_name)` index.

After this feature, nothing under `AgenticRealms.World` or `AgenticRealmsWeb` reads
`accounts.players.username` except the authentication path: `Accounts`, `PlayerAuth`,
`PlayerSessionController`, and the three auth LiveViews. Those are untouched.

---

## Key renames

Two public shapes change, because their names would otherwise describe something they no longer
hold.

| Shape | Was | Becomes |
|---|---|---|
| The maps `World.Queries` returns for players in a room | `%{id: integer(), username: String.t()}` | `%{id: integer(), name: String.t()}` |
| The `World.UIEvents` structs | `actor_username` | `actor_name` |
| `World.WizardTrance` payloads | `wizard_username` | `wizard_name` |

There is no compiler help for a map key rename, so the test suite is the net. That is the argument
for renaming rather than re-populating: a re-populate compiles cleanly forever while every reader
believes it is holding a username.

---

## Every seam

| # | File | Today | After |
|---|---|---|---|
| 1 | `world/queries.ex` | `list_players_in_room/1` and `list_other_players/2` join `accounts.players`, select and order by `p.username` | select and order by `ps.character_name`; the join to `accounts.players` disappears |
| 2 | `world/ui_event_broadcaster.ex` | `lookup_username/1` calls `Accounts.get_player/1` | `PlayerNames.get/1`; fallback stays `"unknown player"` |
| 3 | `world/stats.ex` | `player_name/1` calls `Accounts.get_player/1` | reads `character_name` off the `player_state` row it has already loaded, so the sheet costs one fewer query |
| 4 | `world/examine.ex` | `acting_username/1`; `player_match/1`; the two matchers downcase `p.username` | `PlayerNames.get/1`; match on `:name` |
| 5 | `world/communication.ex` | sender map takes `:username`; broadcasts `actor_username` | `:name`; `actor_name` |
| 6 | `world/communication/recipient_resolver.ex` | resolves a target by username | by character name, via `PlayerNames.find_by_name/1` |
| 7 | `world/ui_events.ex` | `actor_username` on the event structs | `actor_name` |
| 8 | `world/npc_chat/context.ex` | username in the LLM context | character name |
| 9 | `world/intent_resolver/context_snapshot.ex` | username in the resolver snapshot | character name |
| 10 | `world/wizard_trance.ex` | `wizard_username` | `wizard_name` |
| 11 | `web/presence.ex` | `track_player/3` tracks `%{username: ...}` | `%{name: ...}` |
| 12 | `web/live/game_live.ex` | mount reads `current_player.username` and passes it to Presence | passes the character name |
| 13 | `web/live/game_live/ui_events.ex` | reads `actor_username` off the broadcast payloads | `actor_name` |
| 14 | `web/live/game_live/communication.ex` | builds the sender map with `:username` | `:name` |
| 15 | `web/components/game/log_entry.ex` | renders `actor_username` | `actor_name` |
| 16 | `web/components/game/primitives.ex`, `player_modals.ex` | render `username` from presence and occupant lists | `name` |
| 17 | `web/controllers/npc_service_controller.ex` | `&%{... name: &1.username}` | `&%{... name: &1.name}` |

Seam 3 is a small win worth noting: the sheet already has the row in hand, so sourcing the name
from it removes a query rather than adding one.

Seam 17 is the one that could have been a breaking change and is not. The external NPC API already
renames the field to `name` in its JSON response (`npc_service_controller.ex:127`), so the
published contract in `specs/018-external-npc-api/contracts/npc-service-api.md` is unchanged. Only
the source of the value moves.

---

## Ordering changes

`Queries.list_players_in_room/1` and `list_other_players/2` order by the name today. After the
change they order by `character_name` rather than `username`, so the order of occupants in a room
listing changes for any player whose two names differ. This is a visible behaviour change and it is
correct: the list is sorted by what it displays.

---

## What happens to a player with no character

`PlayerNames.get/1` returns `nil`, and every seam above needs a defined answer. The answer is that
the case does not arise in the world: a player without a character is never spawned, so they are
never in a room, never in an occupant list, never a whisper target, and never in a presence list
that another player reads. `GameLive` holds them in the `:creating` phase before
`Commands.spawn/2` is ever called.

The seams keep their existing fallbacks anyway — `"unknown player"` in the broadcaster,
`"Adventurer"` in `Stats` — because a fallback that never fires is cheaper than a crash that
might.

---

## Testing

The existing suite is the coverage, which is the point of doing this as a rename. Roughly fifty
test files reference `username`; the ones under `test/agenticrealms/world/` and
`test/agenticrealms_web/live/` that exercise rooms, communication, examine, presence, and the NPC
API all move to character names and keep asserting the same behaviour.

Two new assertions are worth adding on top:

- `player_names_test.exs`: `get/1` returns `nil` before creation and the name after;
  `find_by_name/1` matches regardless of case; `get_many/1` returns a map keyed by player id.
- One assertion, somewhere a second player can see the first, that the **username never appears**
  in what is rendered to another player (SC-012). Registering with a username and creating a
  character with a different name makes that assertion meaningful.
