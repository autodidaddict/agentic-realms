defmodule AgenticRealms.World.Events.CharacterCreated do
  @moduledoc """
  Feature 020 — a player's character came into being.

  Distinct from `PlayerSpawned`, which means "entered the world" and happens
  every session. A character is made once, and this is the event that says so.

  Carries the whole character rather than a reference to the configuration or
  the content that produced it, so the record stays true no matter what either
  becomes. `hp` equals `max_hp`: a character is created at full health.

  Feature 021 adds the name the player chose, their lineage where their species
  offers one, and `choices` — the picks with no column of their own, keyed by
  the stable key `Srd.Character.choices/1` assigns, so a new kind of choice
  needs no change to this event.
  """

  @derive Jason.Encoder
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
    :hp,
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
    :hp,
    :max_hp,
    choices: %{},
    version: 1
  ]
end
