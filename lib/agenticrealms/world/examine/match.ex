defmodule AgenticRealms.World.Examine.Match do
  @moduledoc """
  Successful examine resolution. `target_kind` discriminates the three
  payload shapes:

    * `:object` — `name` is the object's stored name (`world_objects.name`
      preserved casing); `long_description` is `world_objects.long_description`
      verbatim.
    * `:player` — `name` is the matched player's display username
      (`account_players.username` preserved casing); `long_description` is
      `nil` — the player render branch hard-codes the placeholder body.
    * `:npc` — `name` is the NPC's stored display name; `long_description`
      is `world_npcs.long_description` verbatim. Render contract identical
      in shape to `:object`.

  See `specs/006-examine-objects/data-model.md` §1 and
  `specs/007-static-npcs/data-model.md` §7.
  """

  @enforce_keys [:target_kind, :name]
  defstruct [:target_kind, :name, :long_description, :id, :health_tier, :power_phrase]

  @type t :: %__MODULE__{
          target_kind: :object | :player | :npc,
          name: String.t(),
          long_description: String.t() | nil,
          # NPC clone entity id (telemetry debug identity) OR target player id
          # (feature 019 health/power lookup); nil for objects.
          id: String.t() | integer() | nil,
          # Feature 019 — examine surfaces only qualitative bands, never numbers.
          health_tier: String.t() | nil,
          power_phrase: String.t() | nil
        }
end
