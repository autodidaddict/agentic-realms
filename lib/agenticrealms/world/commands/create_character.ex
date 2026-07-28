defmodule AgenticRealms.World.Commands.CreateCharacter do
  @moduledoc """
  Feature 020 — give a player their SRD character.

  Carries a fully-formed character: the aggregate generates nothing, looks
  nothing up, and defaults nothing. Generation happens in
  `AgenticRealms.World.CharacterGen` before dispatch, so the resulting event
  records what was actually created and changing the configured defaults later
  cannot rewrite what past players were made as.

  Idempotent at the aggregate: dispatched on every mount, it emits only the
  first time. Interactive creation will dispatch this same command with values
  the player chose instead of values the configuration chose.
  """

  @enforce_keys [
    :player_id,
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
end
