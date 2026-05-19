defmodule AgenticRealms.World.Direction do
  @moduledoc """
  Canonical direction handling for the world. Six directions are supported:
  `:north`, `:south`, `:east`, `:west`, `:up`, `:down`.

  The parser, aggregates, and UI event broadcaster all funnel through this
  module so that direction aliases (`"n"`, `"NORTH"`, `"  go north  "`) and
  their string-form persistence (`"north"`) live in exactly one place.

  Inputs to `parse/1` are matched literally against pre-allocated atoms;
  we never call `String.to_atom/1` on user input.
  """

  @canonical [:north, :south, :east, :west, :up, :down]

  @spec canonical() :: [atom()]
  def canonical, do: @canonical

  @doc """
  Parse a direction from text input or an already-canonical atom.

  Strips leading/trailing whitespace, lowercases, optionally consumes a leading
  `go ` prefix, then matches the remainder against the alias table.
  """
  @spec parse(String.t() | atom()) :: {:ok, atom()} | :error
  def parse(dir) when dir in @canonical, do: {:ok, dir}

  def parse(text) when is_binary(text) do
    normalized =
      text
      |> String.trim()
      |> String.downcase()
      |> strip_go_prefix()
      |> String.trim()

    case normalized do
      "north" -> {:ok, :north}
      "n" -> {:ok, :north}
      "south" -> {:ok, :south}
      "s" -> {:ok, :south}
      "east" -> {:ok, :east}
      "e" -> {:ok, :east}
      "west" -> {:ok, :west}
      "w" -> {:ok, :west}
      "up" -> {:ok, :up}
      "u" -> {:ok, :up}
      "down" -> {:ok, :down}
      "d" -> {:ok, :down}
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc """
  Return the opposite of a direction. Used by the UI event broadcaster to
  derive `from_direction` for arrival witness entries.
  """
  @spec opposite(atom()) :: atom()
  def opposite(:north), do: :south
  def opposite(:south), do: :north
  def opposite(:east), do: :west
  def opposite(:west), do: :east
  def opposite(:up), do: :down
  def opposite(:down), do: :up

  @doc """
  Render a direction atom as a lowercase string for the read-model column or
  for display in UI strings.

  Accepts already-stringified directions too so projectors can call this
  uniformly on the deserialized event payload (Commanded's JSON serializer
  turns atom fields into strings during round-trip through the event store).
  """
  @spec to_string(atom() | String.t()) :: String.t()
  def to_string(:north), do: "north"
  def to_string(:south), do: "south"
  def to_string(:east), do: "east"
  def to_string(:west), do: "west"
  def to_string(:up), do: "up"
  def to_string(:down), do: "down"
  def to_string(s) when s in ["north", "south", "east", "west", "up", "down"], do: s

  defp strip_go_prefix("go " <> rest), do: rest
  defp strip_go_prefix(other), do: other
end
