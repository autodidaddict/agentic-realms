defmodule Srd.Rules.DeathSaves do
  @moduledoc """
  Death saving throw rules.

  A creature at 0 hit points makes a death saving throw at the start of each of
  its turns. This tracks the running tally of successes and failures and
  resolves it to stable, dead, or revived.
  """
  alias Srd.Dice.Roll
  alias Srd.Rules.D20

  defstruct successes: 0, failures: 0, status: :dying

  @typedoc """
  The state of a death-save sequence:

  * `:successes` / `:failures` - the running tally (0..3)
  * `:status` - `:dying` while still rolling, then a terminal `:stable`
    (three successes), `:dead` (three failures), or `:revived` (a natural 20,
    which regains 1 hit point)
  """
  @type t :: %__MODULE__{
          successes: 0..3,
          failures: 0..3,
          status: :dying | :stable | :dead | :revived
        }

  @doc """
  A fresh death-save sequence for a creature that has just dropped to 0 HP.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Record one turn's death saving throw against a completed d20 roll.

  A natural 20 revives the creature (regain 1 HP); a natural 1 counts as two
  failures; otherwise a total of 10 or more is a success and anything lower is a
  failure. Three successes stabilize, three failures kill. Recording against a
  sequence that has already settled is a no-op.
  """
  @spec record_save(t(), Roll.t()) :: t()
  def record_save(%__MODULE__{status: :dying} = state, %Roll{} = roll) do
    result = D20.test(roll, 10)

    cond do
      result.natural == 20 -> %{state | status: :revived}
      result.natural == 1 -> add_failure(state, 2)
      result.success? -> add_success(state, 1)
      true -> add_failure(state, 1)
    end
  end

  def record_save(%__MODULE__{} = state, %Roll{}), do: state

  @doc """
  Record a hit taken while at 0 HP: one failure, or two on a critical hit.
  Recording against a settled sequence is a no-op.
  """
  @spec record_damage(t(), keyword()) :: t()
  def record_damage(state, opts \\ [])

  def record_damage(%__MODULE__{status: :dying} = state, opts) do
    add_failure(state, if(Keyword.get(opts, :critical?, false), do: 2, else: 1))
  end

  def record_damage(%__MODULE__{} = state, _opts), do: state

  defp add_success(state, n), do: settle(%{state | successes: min(state.successes + n, 3)})
  defp add_failure(state, n), do: settle(%{state | failures: min(state.failures + n, 3)})

  defp settle(%__MODULE__{successes: 3} = state), do: %{state | status: :stable}
  defp settle(%__MODULE__{failures: 3} = state), do: %{state | status: :dead}
  defp settle(%__MODULE__{} = state), do: state
end
