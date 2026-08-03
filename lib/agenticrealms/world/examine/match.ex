defmodule AgenticRealms.World.Examine.Match do
  @moduledoc """
  Successful examine resolution. `target_kind` discriminates the three
  payload shapes:

    * `:object` — `name` is the object's stored name (`world_objects.name`
      preserved casing); `long_description` is `world_objects.long_description`
      verbatim.
    * `:player` — `name` is the matched player's character name
      (`player_state.character_name`, preserved casing); `long_description` is
      `nil` — the player render branch hard-codes the placeholder body.
    * `:npc` — `name` is the NPC's stored display name; `long_description`
      is `world_npcs.long_description` verbatim. Render contract identical
      in shape to `:object`.
  """

  @enforce_keys [:target_kind, :name]
  defstruct [:target_kind, :name, :long_description, :id, :health_tier, :power_phrase]

  @type t :: %__MODULE__{
          target_kind: :object | :player | :npc,
          name: String.t(),
          long_description: String.t() | nil,
          id: String.t() | integer() | nil,
          health_tier: String.t() | nil,
          power_phrase: String.t() | nil
        }
end
