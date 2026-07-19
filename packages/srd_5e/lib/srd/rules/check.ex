defmodule Srd.Rules.Check do
  @moduledoc """
  Ability check rules
  """
  alias Srd.Dice.Roll
  alias Srd.Rules.D20

  defstruct [:success?, :natural, :total, :dc, :margin]

  @typedoc """
  The result of an ability check: whether it met the DC, plus the values behind
  the outcome. A check is a d20 test against a difficulty class, with no critical
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
  Resolve an ability check against a difficulty class
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

  @doc """
  The passive score for a check: `10 + modifier`, plus 5 for advantage or minus
  5 for disadvantage.
  """
  @spec passive(integer(), keyword()) :: integer()
  def passive(modifier, opts \\ []) do
    10 + modifier + passive_adjustment(Keyword.get(opts, :advantage, :normal))
  end

  defp passive_adjustment(:advantage), do: 5
  defp passive_adjustment(:disadvantage), do: -5
  defp passive_adjustment(:normal), do: 0
end
