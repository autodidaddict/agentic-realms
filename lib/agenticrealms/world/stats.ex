defmodule AgenticRealms.World.Stats do
  @moduledoc """
  Feature 019 — Real Stats: the character-sheet read plus qualitative banding.

  `for_player/1` builds the character-sheet shape (contracts/read-and-display)
  from the `player_state` read model and the `LevelCurve`. `health_tier/2` and
  `relative_power/2` are pure banding helpers used by `Examine` — they surface
  only qualitative bands, never the target's exact numbers (FR-020).
  """

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.LevelCurve
  alias AgenticRealms.World.Schemas.PlayerState

  @ability_order [
    {:str, "Strength"},
    {:dex, "Dexterity"},
    {:con, "Constitution"},
    {:int, "Intelligence"},
    {:wis, "Wisdom"},
    {:cha, "Charisma"}
  ]

  @doc """
  The character-sheet shape for `player_id`:

      %{name, level, xp: %{into_level, to_next, fraction},
        hp: %{cur, max}, mana: %{cur, max},
        abilities: [%{name, value}, ...]}   # 6, STR..CHA order, full names

  Falls back to schema defaults if the player has no `player_state` row yet
  (mount spawns before reading, so this is only a safety net).
  """
  @spec for_player(term()) :: map()
  def for_player(player_id) do
    ps = Repo.get(PlayerState, player_id) || %PlayerState{}
    progress = LevelCurve.progress(ps.xp)

    %{
      name: player_name(player_id),
      level: ps.level,
      xp: %{
        into_level: progress.into_level,
        to_next: progress.to_next,
        fraction: progress.fraction
      },
      hp: %{cur: ps.hp, max: ps.max_hp},
      mana: %{cur: ps.mana, max: ps.max_mana},
      abilities:
        for {field, label} <- @ability_order do
          %{name: label, value: Map.fetch!(ps, field)}
        end
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

  defp player_name(player_id) do
    case Accounts.get_player(player_id) do
      nil -> "Adventurer"
      player -> player.username
    end
  end
end
