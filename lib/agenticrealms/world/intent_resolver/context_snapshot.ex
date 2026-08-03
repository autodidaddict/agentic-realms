defmodule AgenticRealms.World.IntentResolver.ContextSnapshot do
  @moduledoc """
  Builds the volatile per-request user message for the intent resolver — a
  compact markdown rendering of the player's current room, their inventory,
  and their literal input.

  This is the only part of the Anthropic request that varies per call; the
  system prompt and tool definitions are stable.
  """

  alias AgenticRealms.World.Queries

  @description_limit 300

  @doc """
  Build the user-message text for `player_id` issuing `raw_input`.

  Returns `{:ok, text}` or `{:error, :no_current_room}` when the player has
  no resolvable room (should not happen mid-session — `GameLive` spawns the
  player on mount).
  """
  @spec build(integer(), String.t()) :: {:ok, String.t()} | {:error, :no_current_room}
  def build(player_id, raw_input) when is_integer(player_id) and is_binary(raw_input) do
    case Queries.look_room(player_id) do
      {:ok, room} ->
        inventory = Queries.list_inventory(player_id)
        {:ok, render(room, inventory, raw_input)}

      {:error, _} ->
        {:error, :no_current_room}
    end
  end

  @doc """
  Render the user-message text from an already-fetched room view, inventory
  list, and raw input. Pure — no DB. `build/2` wraps this after querying;
  exposed directly so the formatting can be unit-tested without a database.
  """
  @spec render(
          %{
            name: String.t(),
            description: String.t(),
            exits: list(),
            objects: list(),
            other_players: list(),
            npcs: list()
          },
          list(),
          String.t()
        ) :: String.t()
  def render(room, inventory, raw_input) do
    """
    Current room: #{room.name}
    Description: #{truncate(room.description)}
    Exits: #{format_exits(room.exits)}
    Objects here: #{format_names(room.objects)}
    NPCs here: #{format_npcs(room.npcs)}
    Other players present: #{format_names(room.other_players)}
    Your inventory: #{format_inventory(inventory)}

    Player typed: #{raw_input}
    """
    |> String.trim_trailing()
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @description_limit do
      String.slice(text, 0, @description_limit) <> "…"
    else
      text
    end
  end

  defp truncate(_), do: ""

  defp format_exits([]), do: "(none)"

  defp format_exits(exits) do
    Enum.map_join(exits, ", ", fn e -> "#{e.direction} (#{e.target_name})" end)
  end

  defp format_names([]), do: "(none)"
  defp format_names(entries), do: Enum.map_join(entries, ", ", & &1.name)

  defp format_npcs([]), do: "(none)"

  defp format_npcs(npcs) do
    Enum.map_join(npcs, ", ", fn n ->
      case n[:short_description] do
        s when is_binary(s) and s != "" -> "#{n.name} (#{s})"
        _ -> n.name
      end
    end)
  end

  defp format_inventory([]), do: "(empty)"
  defp format_inventory(items), do: Enum.map_join(items, ", ", & &1.name)
end
