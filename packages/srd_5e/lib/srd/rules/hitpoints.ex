defmodule Srd.Rules.Hitpoints do
  @moduledoc """
  Hit point rules.

  Applies damage and healing to a hit point pool, accounting for temporary hit
  points and clamping to the range `0..max_hp`. Each operation reports an outcome
  describing the transition, such as dropping to 0 or dying outright.
  """

  @enforce_keys [:hp, :max_hp]
  defstruct [:hp, :max_hp, temp_hp: 0, outcome: nil]

  @typedoc """
  The outcome of the most recent operation on a hit point pool:

  * `:ok` - hit points remain above 0
  * `:downed` - damage dropped the pool from above 0 to 0
  * `:hit_while_down` - damage was taken while already at 0
  * `:dead` - instant death, when the damage past 0 is at least the maximum
  * `:recovered` - healing brought the pool from 0 back above 0
  """
  @type outcome :: :ok | :downed | :hit_while_down | :dead | :recovered

  @typedoc """
  A hit point pool:

  * `:hp` - current hit points (0..max_hp)
  * `:max_hp` - the hit point maximum
  * `:temp_hp` - temporary hit points, a separate buffer that absorbs damage first
  * `:outcome` - the result of the most recent `damage/2` or `heal/2`, or `nil`
  """
  @type t :: %__MODULE__{
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          temp_hp: non_neg_integer(),
          outcome: outcome() | nil
        }

  @doc """
  Build a hit point pool.
  """
  @spec new(non_neg_integer(), pos_integer(), non_neg_integer()) :: t()
  def new(hp, max_hp, temp_hp \\ 0) do
    %__MODULE__{hp: hp, max_hp: max_hp, temp_hp: temp_hp, outcome: nil}
  end

  @doc """
  Apply damage. Temporary hit points absorb it first and current hit points floor
  at 0. Damage that leaves the pool at 0 with an excess of at least the maximum
  is instant death.
  """
  @spec damage(t(), non_neg_integer()) :: t()
  def damage(%__MODULE__{} = pool, amount) when is_integer(amount) and amount >= 0 do
    was_down = pool.hp == 0

    absorbed = min(pool.temp_hp, amount)
    remaining = amount - absorbed
    new_hp = pool.hp - remaining

    outcome =
      cond do
        remaining == 0 -> :ok
        new_hp > 0 -> :ok
        remaining - pool.hp >= pool.max_hp -> :dead
        was_down -> :hit_while_down
        true -> :downed
      end

    %{pool | hp: max(new_hp, 0), temp_hp: pool.temp_hp - absorbed, outcome: outcome}
  end

  @doc """
  Apply healing, up to the maximum. Temporary hit points are unaffected.
  """
  @spec heal(t(), non_neg_integer()) :: t()
  def heal(%__MODULE__{} = pool, amount) when is_integer(amount) and amount >= 0 do
    new_hp = min(pool.hp + amount, pool.max_hp)
    outcome = if pool.hp == 0 and new_hp > 0, do: :recovered, else: :ok

    %{pool | hp: new_hp, outcome: outcome}
  end
end
