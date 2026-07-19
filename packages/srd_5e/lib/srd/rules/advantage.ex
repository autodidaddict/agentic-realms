defmodule Srd.Rules.Advantage do
  @moduledoc """
  Advantage and disadvantage.
  """

  @typedoc "An advantage state."
  @type state :: :advantage | :disadvantage | :normal

  @doc """
  Net a list of advantage and disadvantage sources into a single state.

  Sources of the same kind don't stack, and any advantage together with any
  disadvantage cancels to `:normal`.
  """
  @spec net([:advantage | :disadvantage]) :: state()
  def net(sources) when is_list(sources) do
    cond do
      :advantage in sources and :disadvantage in sources -> :normal
      :advantage in sources -> :advantage
      :disadvantage in sources -> :disadvantage
      true -> :normal
    end
  end
end
