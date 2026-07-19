defmodule Srd.Content.Conditions do
  @moduledoc """
  SRD conditions, looked up by slug.
  """
  alias Srd.Content.Condition

  @data_file Path.expand("../../../priv/data/conditions.exs", __DIR__)
  @external_resource @data_file

  @conditions @data_file
              |> Code.eval_file()
              |> elem(0)
              |> Map.new(fn data -> {data.slug, Condition.new(data)} end)

  @doc """
  Every condition.
  """
  @spec all() :: [Condition.t()]
  def all, do: Map.values(conditions())

  @doc """
  Look up a condition by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Condition.t() | nil
  def get(slug), do: Map.get(conditions(), slug)

  @doc """
  Look up a condition by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Condition.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no condition with slug #{inspect(slug)}"
      condition -> condition
    end
  end

  defp conditions, do: @conditions
end
