defmodule Srd.Rules.D20 do
  @moduledoc """
  Basic support for the d20 test
  """
  alias Srd.Dice.Roll

  defstruct [:total, :target, :natural, :success?, :margin]

  @typedoc """
  Many rules rely on a simple d20 test that compares a d20 roll total against
  a target number. These rules need the actual value as well as the unmodified
  (natural) roll. The D20 type exposes that functionality to other rules.

  Attack, save, and ability check are all rulesets that rely on the d20 test.
  """
  @type t :: %__MODULE__{
          total: integer(),
          target: integer(),
          natural: 1..20,
          success?: boolean(),
          margin: integer()
        }

  @doc """
  Performs the d20 test against a completed die roll
  """
  @spec test(Roll.t(), integer()) :: t()
  def test(%Roll{sides: 20} = roll, target) do
    natural = roll.total - roll.modifier

    %__MODULE__{
      total: roll.total,
      target: target,
      natural: natural,
      success?: roll.total >= target,
      margin: roll.total - target
    }
  end

  def test(%Roll{sides: s}, _target),
    do: raise(ArgumentError, "d20 test requires a d20 roll, got d#{s}")
end
