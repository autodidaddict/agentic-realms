defmodule Srd.Content.Feature do
  @moduledoc """
  One feature a class, subclass, species, background, or feat grants.

  `:text` is a concise restatement of the feature's mechanics rather than the
  SRD's own prose, the same rule the condition content follows.
  """
  alias Srd.Content.Choice

  @enforce_keys [:name, :text]
  defstruct [:name, :text, :level, :choice]

  @typedoc """
  A granted feature:

  * `:name` - the feature's name
  * `:text` - a restatement of what it does
  * `:level` - the level it arrives at, or `nil` when it comes with the thing
    that grants it, as a feat's benefits do
  * `:choice` - the choice it asks the character to make, if any
  """
  @type t :: %__MODULE__{
          name: String.t(),
          text: String.t(),
          level: pos_integer() | nil,
          choice: Choice.t() | nil
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      name: data.name,
      text: data.text,
      level: data[:level],
      choice: choice(data[:choice])
    }
  end

  @doc """
  The features from `features` that a character of `level` has, in level order.
  Features with no level are always included.
  """
  @spec through_level([t()], pos_integer()) :: [t()]
  def through_level(features, level) do
    features
    |> Enum.filter(&(is_nil(&1.level) or &1.level <= level))
    |> Enum.sort_by(&(&1.level || 0))
  end

  defp choice(nil), do: nil
  defp choice(%Choice{} = choice), do: choice
  defp choice(data), do: Choice.new(data)
end
