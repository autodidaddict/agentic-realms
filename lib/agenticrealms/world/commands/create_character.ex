defmodule AgenticRealms.World.Commands.CreateCharacter do
  @moduledoc """
  Give a player their SRD character.

  Carries a fully-formed character: the aggregate generates nothing, looks
  nothing up, and defaults nothing. Generation happens in
  `AgenticRealms.World.CharacterGen` before dispatch, so the resulting event
  records what was actually created and changing the configured defaults later
  cannot rewrite what past players were made as.

  Idempotent at the aggregate: dispatched once per confirmation, it emits only
  the first time.

  The values are the player's own. `AgenticRealms.World.
  Commands.create_character/2` completes their draft, validates it, claims the
  name, and dispatches this. Generation still fills whatever the dialog has not
  learned to ask.
  """

  @enforce_keys [
    :player_id,
    :character_name,
    :species_slug,
    :class_slug,
    :background_slug,
    :size,
    :abilities,
    :skill_proficiencies,
    :save_proficiencies,
    :feat_slugs,
    :max_hp
  ]
  defstruct [
    :player_id,
    :character_name,
    :species_slug,
    :class_slug,
    :background_slug,
    :size,
    :lineage_slug,
    :abilities,
    :skill_proficiencies,
    :save_proficiencies,
    :feat_slugs,
    :max_hp,
    choices: %{}
  ]
end
