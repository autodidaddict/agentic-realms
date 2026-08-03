defmodule AgenticRealmsWeb.NpcServiceController do
  @moduledoc """
  The game-exposed NPC service contract consumed by the external
  mind worker (`agentic-realms-npc`). Three authenticated routes: read identity,
  read surroundings, submit a move. Guarded by `RequireServiceToken`.

  match the shared schema in `agentic-realms-npc` feature 001.
  """

  use AgenticRealmsWeb, :controller

  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, ContainerRef, Queries}
  alias AgenticRealms.World.Schemas.NPCClone

  def identity(conn, %{"id" => id}) do
    case get_npc(id) do
      %NPCClone{} = npc ->
        json(conn, %{
          entity_id: npc.id,
          name: npc.name,
          short_description: npc.short_description,
          long_description: npc.long_description,
          lore: npc.lore || ""
        })

      nil ->
        not_found(conn)
    end
  end

  def surroundings(conn, %{"id" => id}) do
    case get_npc(id) do
      %NPCClone{room_id: nil, id: eid} ->
        json(conn, %{entity_id: eid, room_id: nil, exits: [], occupants: []})

      %NPCClone{room_id: room_id, id: eid} ->
        json(conn, %{
          entity_id: eid,
          room_id: room_id,
          exits: exits_for(room_id),
          occupants: occupants_for(room_id)
        })

      nil ->
        not_found(conn)
    end
  end

  def move(conn, %{"id" => id} = params) do
    expected_room_id = params["expected_room_id"]

    case get_npc(id) do
      nil ->
        not_found(conn)

      %NPCClone{} ->
        case resolve_exit(expected_room_id, params["direction"]) do
          nil -> no_such_exit(conn)
          to_room_id -> enact_move(conn, id, expected_room_id, to_room_id)
        end
    end
  end

  defp enact_move(conn, id, expected_room_id, to_room_id) do
    case Commands.move_entity(
           id,
           ContainerRef.room(expected_room_id),
           ContainerRef.room(to_room_id),
           :relocated
         ) do
      :ok ->
        json(conn, %{result: "ok", from_room_id: expected_room_id, to_room_id: to_room_id})

      {:error, :container_conflict} ->
        conn |> put_status(:conflict) |> json(%{result: "conflict"})

      {:error, :not_found} ->
        not_found(conn)

      {:error, _other} ->
        no_such_exit(conn)
    end
  end

  defp get_npc(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(NPCClone, uuid)
      :error -> nil
    end
  end

  defp resolve_exit(room_id, direction)
       when is_binary(room_id) and is_binary(direction) do
    Queries.list_global_exits(room_id)
    |> Enum.find_value(fn %{direction: d, target_room_id: t} -> if d == direction, do: t end)
  end

  defp resolve_exit(_room_id, _direction), do: nil

  defp exits_for(room_id) do
    Queries.list_global_exits(room_id)
    |> Enum.map(fn %{direction: d, target_room_id: t} -> %{direction: d, to_room_id: t} end)
  end

  defp occupants_for(room_id) do
    npcs = Enum.map(Queries.list_npcs_in_room(room_id), &%{id: &1.id, kind: "npc", name: &1.name})

    objects =
      Enum.map(
        Queries.list_objects_in_room(room_id),
        &%{id: &1.id, kind: "object", name: &1.name}
      )

    players =
      Enum.map(
        Queries.list_players_in_room(room_id),
        &%{id: Integer.to_string(&1.id), kind: "player", name: &1.name}
      )

    npcs ++ objects ++ players
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp no_such_exit(conn),
    do: conn |> put_status(:unprocessable_entity) |> json(%{result: "no_such_exit"})
end
