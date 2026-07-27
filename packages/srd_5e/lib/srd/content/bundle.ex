defmodule Srd.Content.Bundle do
  @moduledoc """
  One starting equipment option: some gear, some gold, and any pieces the
  character still picks for themselves.

  Item slugs are resolved against weapons, armor, and items while compiling, so
  every entry in a bundle names something that exists.
  """
  alias Srd.Content.Armors
  alias Srd.Content.Choice
  alias Srd.Content.Items
  alias Srd.Content.Weapons

  @enforce_keys [:items, :gp]
  defstruct items: [], choices: [], gp: 0

  @typedoc """
  An entry in a bundle: what it is, how many, and which form it takes when the
  item comes in more than one (an Arcane Focus that is a crystal, say).
  """
  @type entry :: %{
          item: String.t(),
          quantity: pos_integer(),
          variant: String.t() | nil
        }

  @typedoc """
  A starting equipment option:

  * `:items` - the gear it grants outright
  * `:choices` - the pieces the character still chooses, such as a Bard's
    instrument
  * `:gp` - the gold it grants alongside the gear
  """
  @type t :: %__MODULE__{
          items: [entry()],
          choices: [Choice.t()],
          gp: non_neg_integer()
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      items: Enum.map(data[:items] || [], &entry/1),
      choices: Enum.map(data[:choices] || [], &Choice.new/1),
      gp: data[:gp] || 0
    }
  end

  @doc false
  @spec choice(map()) :: Choice.t()
  def choice(data) do
    Choice.new(%{data | from: Enum.map(data.from, &new/1)})
  end

  @doc """
  Whether a slug names a weapon, a piece of armor, or an item.
  """
  @spec known?(String.t()) :: boolean()
  def known?(slug) do
    Weapons.get(slug) != nil or Armors.get(slug) != nil or Items.get(slug) != nil
  end

  defp entry({slug, quantity}), do: entry(%{item: slug, quantity: quantity})
  defp entry(slug) when is_binary(slug), do: entry(%{item: slug, quantity: 1})

  defp entry(%{item: slug} = data) do
    unless known?(slug) do
      raise ArgumentError, "bundle names unknown item #{inspect(slug)}"
    end

    %{item: slug, quantity: data[:quantity] || 1, variant: data[:variant]}
  end
end
