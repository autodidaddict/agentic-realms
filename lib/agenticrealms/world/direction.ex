defmodule AgenticRealms.World.Direction do
  @moduledoc """
  Canonical direction handling for the world. Ten directions are supported:
  the four cardinals (`:north`, `:south`, `:east`, `:west`), the four
  diagonals (`:northeast`, `:northwest`, `:southeast`, `:southwest`), and
  the two verticals (`:up`, `:down`).

  The parser, aggregates, and UI event broadcaster all funnel through this
  module so that direction aliases (`"n"`, `"NORTH"`, `"  go north  "`) and
  their string-form persistence (`"north"`) live in exactly one place.

  Inputs to `parse/1` are matched literally against pre-allocated atoms;
  we never call `String.to_atom/1` on user input.

  Feature 012 (maps) added the four diagonals. Geometric semantics — coord
  deltas, fog-stub angles, exit-validation rules — live in
  `AgenticRealms.World.Direction.Geometry`. This module remains a pure
  name/parse/opposite/serialize helper with no coordinate awareness.
  """

  @canonical [
    :north,
    :south,
    :east,
    :west,
    :northeast,
    :northwest,
    :southeast,
    :southwest,
    :up,
    :down
  ]

  @canonical_strings ~w(north south east west northeast northwest southeast southwest up down)

  @spec canonical() :: [atom()]
  def canonical, do: @canonical

  @doc """
  Parse a direction from text input or an already-canonical atom.

  Strips leading/trailing whitespace, lowercases, optionally consumes a leading
  `go ` prefix, then matches the remainder against the alias table.
  """
  @spec parse(String.t() | atom()) :: {:ok, atom()} | :error
  def parse(dir) when dir in @canonical, do: {:ok, dir}

  # Feature 017 — `:rift` is a non-geographic portal direction used only by a
  # transient region's owner-only entry exit. It is deliberately NOT in
  # `@canonical` (so the compass map/geometry code never treats it as a
  # navigable cardinal), but the parser/serializer recognize it so movement,
  # exit listing, and the read-model column round-trip work.
  def parse(:rift), do: {:ok, :rift}

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
      "northeast" -> {:ok, :northeast}
      "ne" -> {:ok, :northeast}
      "northwest" -> {:ok, :northwest}
      "nw" -> {:ok, :northwest}
      "southeast" -> {:ok, :southeast}
      "se" -> {:ok, :southeast}
      "southwest" -> {:ok, :southwest}
      "sw" -> {:ok, :southwest}
      "up" -> {:ok, :up}
      "u" -> {:ok, :up}
      "down" -> {:ok, :down}
      "d" -> {:ok, :down}
      "rift" -> {:ok, :rift}
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
  def opposite(:northeast), do: :southwest
  def opposite(:southwest), do: :northeast
  def opposite(:northwest), do: :southeast
  def opposite(:southeast), do: :northwest
  def opposite(:up), do: :down
  def opposite(:down), do: :up
  # A rift is its own inverse — stepping back through it returns whence you came.
  def opposite(:rift), do: :rift

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
  def to_string(:northeast), do: "northeast"
  def to_string(:northwest), do: "northwest"
  def to_string(:southeast), do: "southeast"
  def to_string(:southwest), do: "southwest"
  def to_string(:up), do: "up"
  def to_string(:down), do: "down"
  def to_string(:rift), do: "rift"
  def to_string("rift"), do: "rift"
  def to_string(s) when s in @canonical_strings, do: s

  defp strip_go_prefix("go " <> rest), do: rest
  defp strip_go_prefix(other), do: other
end
