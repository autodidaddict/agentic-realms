defmodule Srd.Content.Subclass do
  @moduledoc """
  An SRD subclass.

  A subclass belongs to exactly one class and is chosen at that class's
  `:subclass_level`. The SRD carries one subclass per class.
  """
  alias Srd.Content.Feature

  @enforce_keys [:slug, :name, :class]
  defstruct [:slug, :name, :class, features: []]

  @typedoc """
  An SRD subclass:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:class` - the slug of the class it belongs to
  * `:features` - what it grants, by level
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          class: String.t(),
          features: [Feature.t()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      class: data.class,
      features: Enum.map(data[:features] || [], &Feature.new/1)
    }
  end
end
