defmodule Srd.Content.Weapons do
  @moduledoc """
  SRD weapons, looked up by slug.
  """
  alias Srd.Content.Weapon

  @data_file Path.expand("../../../priv/data/weapons.exs", __DIR__)
  @external_resource @data_file

  @weapons @data_file
           |> Code.eval_file()
           |> elem(0)
           |> Map.new(fn data -> {data.slug, Weapon.new(data)} end)

  @doc """
  Every weapon.
  """
  @spec all() :: [Weapon.t()]
  def all, do: Map.values(weapons())

  @doc """
  Look up a weapon by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Weapon.t() | nil
  def get(slug), do: Map.get(weapons(), slug)

  @doc """
  Look up a weapon by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Weapon.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no weapon with slug #{inspect(slug)}"
      weapon -> weapon
    end
  end

  defp weapons, do: @weapons
end
