defmodule AgenticRealms.World.Stats do
  @moduledoc """
  Feature 020 — the character-sheet read, plus the qualitative banding examine
  uses.

  `for_player/1` is an adapter and nothing more: it reads the `player_state`
  row, hands the facts to `Srd.Character.derive/1`, and merges in the two things
  the SRD does not own — the character's name and their current hitpoints. Every
  number on the sheet comes from the rules package; no SRD arithmetic happens in
  this module or anywhere else in the game.

  `health_tier/2` and `relative_power/2` are pure banding helpers used by
  `Examine`. They surface only qualitative bands, never the target's exact
  numbers (FR-025), and are unchanged from feature 019.
  """

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.PlayerState
  alias Srd.Rules.Ability
  alias Srd.Rules.Skill

  @sizes ~w(tiny small medium large huge gargantuan)a

  @doc """
  The character-sheet shape for `player_id`.

  Returns the map `Srd.Character.derive/1` produces, plus `:name`, `:hp` (the
  current pool against its derived maximum), and `:xp` (the experience block,
  named for the UI that renders it).

  `overrides` may carry `:level` and `:xp` to derive against values the caller
  knows are ahead of the read model. Progression is broadcast by an `:eventual`
  handler, so a socket reacting to a level-up can hold the authoritative new
  level before the projector has written it; passing it here avoids re-deriving
  a sheet one level stale. Everything else still comes from the row.

  Raises if the player has no character. `GameLive.mount` dispatches
  `Commands.ensure_character/1` at `:strong` consistency before reading, so a
  missing character here means the read model and the aggregate have diverged —
  the same class of failure `mount` already raises on for a missing room.
  """
  @spec for_player(integer(), map()) :: map()
  def for_player(player_id, overrides \\ %{}) do
    ps = Repo.get(PlayerState, player_id) || missing!(player_id, "no player_state row")

    if is_nil(ps.species_slug) do
      missing!(player_id, "player_state row has no character")
    end

    ps
    |> facts()
    |> Map.merge(Map.take(overrides, [:level, :xp]))
    |> sheet(ps.character_name || "Adventurer", ps.hp)
  end

  @doc """
  A character sheet from a set of facts, a name, and current hitpoints.

  The one adapter over `Srd.Character.derive/1`, and the reason feature 021's
  review cannot disagree with the sheet it previews: both go through here, so
  "the reviewed character and the created character are identical" is a
  property of the code rather than of two implementations kept in step.

  `hp` of `nil` means full, which is what a character not yet created has.
  """
  @spec sheet(map(), String.t(), integer() | nil) :: map()
  def sheet(facts, name, hp \\ nil) do
    derived = Srd.Character.derive(facts)

    derived
    |> Map.delete(:experience)
    |> Map.merge(%{
      name: name,
      hp: %{cur: hp || derived.max_hit_points, max: derived.max_hit_points},
      xp: derived.experience
    })
  end

  defp facts(%PlayerState{} = ps) do
    %{
      species: ps.species_slug,
      class: ps.class_slug,
      background: ps.background_slug,
      size: to_known(ps.size, @sizes, "size"),
      level: ps.level,
      xp: ps.xp,
      abilities: %{
        str: ps.str,
        dex: ps.dex,
        con: ps.con,
        int: ps.int,
        wis: ps.wis,
        cha: ps.cha
      },
      skill_proficiencies: Enum.map(ps.skill_proficiencies, &to_known(&1, Skill.all(), "skill")),
      save_proficiencies:
        Enum.map(ps.save_proficiencies, &to_known(&1, Ability.all(), "ability")),
      armor: nil,
      shield: nil
    }
  end

  @doc """
  Qualitative health tier from current/maximum hitpoints, as `{atom, sentence}`.
  Bands (by % of max HP): >=90 Very healthy; 65-89 Healthy; 35-64 Weakened;
  10-34 Very Weakened; <10 (incl. 0) At death's door.
  """
  @spec health_tier(integer(), integer()) :: {atom(), String.t()}
  def health_tier(_cur, max) when max <= 0, do: {:deaths_door, "At death's door"}

  def health_tier(cur, max) do
    pct = cur / max * 100

    cond do
      pct >= 90 -> {:very_healthy, "Very healthy"}
      pct >= 65 -> {:healthy, "Healthy"}
      pct >= 35 -> {:weakened, "Weakened"}
      pct >= 10 -> {:very_weakened, "Very Weakened"}
      true -> {:deaths_door, "At death's door"}
    end
  end

  @doc """
  Qualitative power of a target relative to the examiner, from the level delta
  `target_level - examiner_level`. Bands: <=-4 Much weaker; -3..-2 weaker;
  -1..+1 about as powerful; +2..+3 more powerful; >=+4 too powerful to even compare.
  """
  @spec relative_power(integer(), integer()) :: String.t()
  def relative_power(examiner_level, target_level) do
    case target_level - examiner_level do
      d when d <= -4 -> "Much weaker"
      d when d <= -2 -> "weaker"
      d when d <= 1 -> "about as powerful"
      d when d <= 3 -> "more powerful"
      _ -> "too powerful to even compare"
    end
  end

  defp to_known(value, known, kind) do
    Enum.find(known, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "player_state holds an unknown #{kind}: #{inspect(value)}"
  end

  defp missing!(player_id, why) do
    raise "Stats.for_player/1: #{why} for player #{player_id} — " <>
            "ensure_character/1 must be dispatched before reading the sheet"
  end
end
