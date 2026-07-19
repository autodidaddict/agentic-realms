defmodule Srd.Content.Condition do
  @moduledoc """
  An SRD condition.
  """
  @enforce_keys [:slug, :name, :effects]
  defstruct [:slug, :name, :effects]

  @typedoc """
  An SRD condition:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:effects` - the condition's effects, one statement per entry
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          effects: [String.t()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{slug: data.slug, name: data.name, effects: data.effects}
  end
end
