defmodule Srd.Rules.Attack do
  @moduledoc """
  Attack rules
  """
  alias Srd.Dice.Roll
  alias Srd.Rules.D20

  defstruct [:hit?, :critical?, :natural, :total, :target_ac]

  @typedoc """
  Represents the results of evaluating an attack rule
  """
  @type t :: %__MODULE__{
          hit?: boolean(),
          critical?: boolean(),
          natural: pos_integer(),
          total: pos_integer(),
          target_ac: pos_integer()
        }

  @doc """
  Resolve a single attack based on a dice roll and the target's AC
  """
  @spec resolve(Roll.t(), target_ac: integer()) :: t()
  def resolve(%Roll{} = roll, target_ac: ac) do
    t = D20.test(roll, ac)

    {hit?, crit?} =
      cond do
        t.natural == 20 -> {true, true}
        t.natural == 1 -> {false, false}
        true -> {t.success?, false}
      end

    %__MODULE__{hit?: hit?, critical?: crit?, natural: t.natural, total: t.total, target_ac: ac}
  end
end
