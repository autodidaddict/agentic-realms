defmodule Srd.Rules.Exhaustion do
  @moduledoc """
  Exhaustion.
  """

  @enforce_keys [:level, :d20_penalty, :speed_penalty, :dead?]
  defstruct [:level, :d20_penalty, :speed_penalty, :dead?]

  @typedoc """
  The effect of an exhaustion level:

  * `:level` - the exhaustion level (0..6)
  * `:d20_penalty` - the penalty applied to every d20 test
  * `:speed_penalty` - the reduction to Speed, in feet
  * `:dead?` - whether the level is fatal
  """
  @type t :: %__MODULE__{
          level: 0..6,
          d20_penalty: integer(),
          speed_penalty: integer(),
          dead?: boolean()
        }

  @doc """
  The effect of an exhaustion `level` (0–6) under SRD 5.2: every d20 test is
  reduced by 2 per level, Speed drops by 5 feet per level, and level 6 is fatal.
  """
  @spec effect(0..6) :: t()
  def effect(level) when is_integer(level) and level >= 0 and level <= 6 do
    %__MODULE__{
      level: level,
      d20_penalty: -2 * level,
      speed_penalty: -5 * level,
      dead?: level >= 6
    }
  end
end
