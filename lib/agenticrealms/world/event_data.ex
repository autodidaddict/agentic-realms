defmodule AgenticRealms.World.EventData do
  @moduledoc """
  Reading fields out of an event's payload map, whichever way it was keyed.

  Persisted events come back from the event store JSON-decoded with **string**
  keys; the same event handed straight to a handler in a test, or read before it
  has round-tripped, carries **atom** keys. Consumers should not have to care
  which, and three modules had each grown their own copy of this to avoid it —
  `WorldProjector`, `UIEventBroadcaster`, and `Quests`, byte-identical apart
  from the path-walking clause only `Quests` needed.

  This is not a licence to read raw event data for business decisions, which
  Principle II forbids. It is for the denormalized payload maps events carry
  (`fields`, `snapshot`, `criteria`) whose shape is data rather than schema.
  """

  @typedoc "A key, or a path of keys to walk."
  @type key :: String.t() | [String.t()]

  @doc """
  Fetch `key` from `map`, trying the string key first and the atom second.

  Returns `nil` for a missing key, a `nil` map, or an atom that does not exist
  — an unknown key cannot be a hit, and `String.to_existing_atom/1` raising is
  the cheapest way to know that without minting an atom from untrusted input.

      iex> AgenticRealms.World.EventData.get(%{"name" => "lantern"}, "name")
      "lantern"

      iex> AgenticRealms.World.EventData.get(%{name: "lantern"}, "name")
      "lantern"

      iex> AgenticRealms.World.EventData.get(%{"a" => %{"b" => 1}}, ["a", "b"])
      1

      iex> AgenticRealms.World.EventData.get(nil, "name")
      nil
  """
  @spec get(map() | nil | term(), key()) :: term()
  def get(nil, _key), do: nil

  def get(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil -> atom_key(map, key)
      value -> value
    end
  end

  def get(map, [key | rest]) when is_map(map) do
    case get(map, key) do
      nil -> nil
      next -> get(next, rest)
    end
  end

  def get(value, []), do: value
  def get(_other, _key), do: nil

  @doc """
  Fetch `key` and return it only if it is a list, `[]` otherwise.

      iex> AgenticRealms.World.EventData.list(%{"tags" => ["a"]}, "tags")
      ["a"]

      iex> AgenticRealms.World.EventData.list(%{"tags" => "a"}, "tags")
      []
  """
  @spec list(map() | nil | term(), key()) :: list()
  def list(map, key) do
    case get(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp atom_key(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
