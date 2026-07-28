defmodule Srd.Rules.Save do
  @moduledoc """
  Saving throw rules
  """
  alias Srd.Dice.Roll
  alias Srd.Rules.D20

  defstruct [:success?, :natural, :total, :dc, :margin]

  @typedoc """
  The result of a saving throw: whether it met the DC, plus the values behind
  the outcome. A save is a d20 test against a difficulty class, with no critical
  semantics.
  """
  @type t :: %__MODULE__{
          success?: boolean(),
          natural: 1..20,
          total: integer(),
          dc: integer(),
          margin: integer()
        }

  @doc """
  The modifier for a saving throw: the ability modifier, plus the proficiency
  bonus if the character is proficient in that save.

  Mirrors `Srd.Rules.Skill.check_modifier/3` so the two read alike at a call
  site. Saves have no expertise.

      iex> Srd.Rules.Save.modifier(3, 2, proficient?: true)
      5
  """
  @spec modifier(integer(), integer(), keyword()) :: integer()
  def modifier(ability_modifier, proficiency, opts \\ []) do
    if Keyword.get(opts, :proficient?, false) do
      ability_modifier + proficiency
    else
      ability_modifier
    end
  end

  @doc """
  Resolve a saving throw against a difficulty class
  """
  @spec resolve(Roll.t(), dc: integer()) :: t()
  def resolve(%Roll{} = roll, dc: dc) do
    t = D20.test(roll, dc)

    %__MODULE__{
      success?: t.success?,
      natural: t.natural,
      total: t.total,
      dc: dc,
      margin: t.margin
    }
  end
end
