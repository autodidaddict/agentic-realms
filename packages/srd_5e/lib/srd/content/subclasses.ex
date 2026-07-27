defmodule Srd.Content.Subclasses do
  @moduledoc """
  SRD subclasses, looked up by slug.

  Every subclass's class is checked against `Srd.Content.Classes` while
  compiling, so `for_class/1` can only ever name a real class.
  """
  alias Srd.Content.Classes
  alias Srd.Content.Subclass

  @data_file Path.expand("../../../priv/data/subclasses.exs", __DIR__)
  @external_resource @data_file

  @subclasses @data_file
              |> Code.eval_file()
              |> elem(0)
              |> Map.new(fn data -> {data.slug, Subclass.new(data)} end)

  for {slug, subclass} <- @subclasses do
    unless Classes.get(subclass.class) do
      raise ArgumentError, "#{slug} belongs to unknown class #{inspect(subclass.class)}"
    end
  end

  @doc """
  Every subclass.
  """
  @spec all() :: [Subclass.t()]
  def all, do: Map.values(subclasses())

  @doc """
  The subclasses a class can choose from.

  Takes a class slug or a `Srd.Content.Class`, and returns `[]` for anything
  with no subclasses.

      iex> Srd.Content.Subclasses.for_class("fighter") |> Enum.map(& &1.name)
      ["Champion"]
  """
  @spec for_class(String.t() | Srd.Content.Class.t()) :: [Subclass.t()]
  def for_class(%Srd.Content.Class{slug: slug}), do: for_class(slug)

  def for_class(slug) when is_binary(slug) do
    all() |> Enum.filter(&(&1.class == slug)) |> Enum.sort_by(& &1.slug)
  end

  @doc """
  Look up a subclass by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Subclass.t() | nil
  def get(slug), do: Map.get(subclasses(), slug)

  @doc """
  Look up a subclass by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Subclass.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no subclass with slug #{inspect(slug)}"
      subclass -> subclass
    end
  end

  defp subclasses, do: @subclasses
end
