defmodule AgenticRealms.World.Events.CharacterCreated do
  @moduledoc """
  Feature 020 — a player's character came into being.

  Distinct from `PlayerSpawned`, which means "entered the world" and happens
  every session. A character is made once, and this is the event that says so.

  Carries the whole character rather than a reference to the configuration that
  produced it, so the record stays true no matter what the defaults become.
  `hp` equals `max_hp`: a character is created at full health (FR-013).
  """

  @derive Jason.Encoder
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
    :hp,
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
    :hp,
    :max_hp,
    version: 1
  ]
end
