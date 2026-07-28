defmodule Srd.Rules.Hitpoints do
  @moduledoc """
  Hit point rules.

  Applies damage and healing to a hit point pool, accounting for temporary hit
  points and clamping to the range `0..max_hp`. Each operation reports an outcome
  describing the transition, such as dropping to 0 or dying outright.

  Also sizes the pool: `starting/2`, `per_level/2`, and `maximum/3` answer how
  large a character's hit point maximum should be, and `hit_dice/2` gives the
  dice they spend on a rest.
  """

  alias Srd.Dice.Expr

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

  @doc """
  The hit point maximum at level 1: the hit die's maximum plus the Constitution
  modifier, floored at 1.

  The floor matters. The SRD has no notion of a character created at 0 hit
  points, and a low-Constitution wizard would otherwise start dead.

      iex> Srd.Rules.Hitpoints.starting("1d10", 2)
      12
  """
  @spec starting(Expr.t() | String.t(), integer()) :: pos_integer()
  def starting(hit_die, con_modifier) when is_integer(con_modifier) do
    %Expr{sides: sides} = Expr.parse!(hit_die)
    max(sides + con_modifier, 1)
  end

  @doc """
  Hit points gained per level after the first, using the SRD's fixed-value
  option: half the die rounded up, plus one, plus the Constitution modifier.

  Not floored — a character whose per-level gain is zero or negative is a legal,
  if unfortunate, SRD character. The floor belongs on the total.

      iex> Srd.Rules.Hitpoints.per_level("1d10", 2)
      8
  """
  @spec per_level(Expr.t() | String.t(), integer()) :: integer()
  def per_level(hit_die, con_modifier) when is_integer(con_modifier) do
    %Expr{sides: sides} = Expr.parse!(hit_die)
    div(sides, 2) + 1 + con_modifier
  end

  @doc """
  The hit point maximum for a character of `level` levels in one class, floored
  at 1.

  Multiclassing is out of scope: this takes one die and one level.

      iex> Srd.Rules.Hitpoints.maximum("1d10", 3, 2)
      28
  """
  @spec maximum(Expr.t() | String.t(), pos_integer(), integer()) :: pos_integer()
  def maximum(hit_die, level, con_modifier)
      when is_integer(level) and level >= 1 and is_integer(con_modifier) do
    expr = Expr.parse!(hit_die)
    total = starting(expr, con_modifier) + (level - 1) * per_level(expr, con_modifier)
    max(total, 1)
  end

  @doc """
  A character's hit dice pool: the class die with its count set to the level.

  Returned as an expression rather than a string so a caller can roll it
  directly on a short rest, and so rendering stays the caller's choice.

      iex> Srd.Rules.Hitpoints.hit_dice("1d10", 3)
      %Srd.Dice.Expr{count: 3, sides: 10, modifier: 0}
  """
  @spec hit_dice(Expr.t() | String.t(), pos_integer()) :: Expr.t()
  def hit_dice(hit_die, level) when is_integer(level) and level >= 1 do
    %Expr{Expr.parse!(hit_die) | count: level}
  end
end
