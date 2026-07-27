defmodule Srd.Content.Choice do
  @moduledoc """
  One decision a character makes.

  Skill proficiencies, tool proficiencies, starting equipment, an elf's lineage,
  and a fighter's fighting style are all the same shape: pick `choose` of
  `from`. Content carries choices rather than prose so a caller can present the
  options without parsing anything.

  What sits in `from` follows the `kind`: skills and abilities are atoms, tools,
  feats, and weapons are slugs, equipment holds `Srd.Content.Bundle` structs,
  lineages hold `Srd.Content.Lineage` structs, and features hold option names.

  Content data can write `from: {:items, category}`, `{:feats, category}`, or
  `{:weapons, filters}` in place of a list, which expands to the matching slugs.
  It is how "one kind of gaming set", "a Fighting Style feat", or "two melee
  weapons" stays a list of real slugs without repeating them in every file that
  offers the choice.
  """
  alias Srd.Content.Feats
  alias Srd.Content.Items
  alias Srd.Content.Weapons

  @kinds ~w(ability equipment feat feature lineage skill tool weapon)a

  @enforce_keys [:kind, :choose, :from]
  defstruct [:kind, :choose, :from]

  @type kind :: :ability | :equipment | :feat | :feature | :lineage | :skill | :tool | :weapon

  @typedoc """
  A choice:

  * `:kind` - what is being chosen
  * `:choose` - how many to pick
  * `:from` - the options to pick from
  """
  @type t :: %__MODULE__{
          kind: kind(),
          choose: pos_integer(),
          from: [term()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      kind: validate_kind!(data.kind),
      choose: data.choose,
      from: expand(data.from)
    }
  end

  defp expand({:items, category}), do: Items.slugs(category)
  defp expand({:feats, category}), do: Feats.slugs(category)
  defp expand({:weapons, filters}), do: Weapons.slugs(filters)
  defp expand(from) when is_list(from), do: from

  @doc """
  The options a choice offers.
  """
  @spec options(t()) :: [term()]
  def options(%__MODULE__{from: from}), do: from

  @doc """
  Whether the choice is settled: there are exactly as many options as picks, so
  the caller has nothing to decide.

      iex> Srd.Content.Backgrounds.get("acolyte").tool |> Srd.Content.Choice.fixed?()
      true

      iex> Srd.Content.Backgrounds.get("soldier").tool |> Srd.Content.Choice.fixed?()
      false
  """
  @spec fixed?(t()) :: boolean()
  def fixed?(%__MODULE__{choose: choose, from: from}), do: length(from) <= choose

  defp validate_kind!(kind) when kind in @kinds, do: kind

  defp validate_kind!(kind),
    do: raise(ArgumentError, "unknown choice kind: #{inspect(kind)}")
end
