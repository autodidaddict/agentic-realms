defmodule Srd.Rules.Damage do
  @moduledoc """
  Damage resolution.

  Resolves a completed damage roll into a final amount after applying the
  target's resistances, vulnerabilities, and immunities to the damage type.
  """
  alias Srd.Dice.Roll

  @damage_types ~w(acid bludgeoning cold fire force lightning necrotic piercing
                   poison psychic radiant slashing thunder)a

  defstruct [:type, :raw, :final]

  @typedoc "One of the SRD damage types."
  @type damage_type ::
          :acid
          | :bludgeoning
          | :cold
          | :fire
          | :force
          | :lightning
          | :necrotic
          | :piercing
          | :poison
          | :psychic
          | :radiant
          | :slashing
          | :thunder

  @typedoc """
  A defense a target has against certain damage types. Each is a list of the
  types it covers: `:immune` negates, `:resist` halves, `:vulnerable` doubles.
  """
  @type option ::
          {:immune, [damage_type()]}
          | {:resist, [damage_type()]}
          | {:vulnerable, [damage_type()]}

  @typedoc "The defenses accepted by `resolve/3`."
  @type options :: [option()]

  @typedoc """
  The result of resolving damage:

  * `:type` - the damage type
  * `:raw` - the amount rolled, before defenses
  * `:final` - the amount after resistance, vulnerability, or immunity
  """
  @type t :: %__MODULE__{
          type: damage_type(),
          raw: non_neg_integer(),
          final: non_neg_integer()
        }

  @doc """
  The SRD damage types.
  """
  @spec types() :: [damage_type()]
  def types, do: @damage_types

  @doc """
  Resolve a damage roll of the given `type` against a target's defenses.

  Immunity yields no damage, resistance halves it (rounded down), and
  vulnerability doubles it.
  """
  @spec resolve(Roll.t(), damage_type(), options()) :: t()
  def resolve(%Roll{} = roll, type, opts \\ []) do
    validate_type!(type)
    raw = max(roll.total, 0)

    %__MODULE__{type: type, raw: raw, final: apply_defenses(raw, type, opts)}
  end

  defp validate_type!(type) when type in @damage_types, do: type
  defp validate_type!(type), do: raise(ArgumentError, "unknown damage type: #{inspect(type)}")

  defp apply_defenses(raw, type, opts) do
    cond do
      type in Keyword.get(opts, :immune, []) -> 0
      type in Keyword.get(opts, :resist, []) -> div(raw, 2)
      type in Keyword.get(opts, :vulnerable, []) -> raw * 2
      true -> raw
    end
  end
end
