defmodule AgenticRealms.World.Queries do
  @moduledoc """
  Read-side API for the world. Every query is a pure Ecto read against the
  read models in `AgenticRealms.Repo` — no Commanded dispatch, no events.

  See `specs/003-persisted-world/data-model.md` §4 for the contract.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.Accounts.Player, as: AccountPlayer
  alias AgenticRealms.World.RoomView
  alias AgenticRealms.World.Schemas.{Room, Exit, Object, PlayerState}

  @spec current_room_of(integer()) :: {:ok, String.t()} | {:error, :no_current_room}
  def current_room_of(player_id) when is_integer(player_id) do
    case Repo.get(PlayerState, player_id) do
      nil -> {:error, :no_current_room}
      %PlayerState{current_room_id: nil} -> {:error, :no_current_room}
      %PlayerState{current_room_id: room_id} -> {:ok, room_id}
    end
  end

  @spec look_room(integer()) :: {:ok, RoomView.t()} | {:error, :no_current_room | :room_missing}
  def look_room(player_id) when is_integer(player_id) do
    with {:ok, room_id} <- current_room_of(player_id),
         %Room{} = room <- Repo.get(Room, room_id) do
      {:ok,
       %RoomView{
         id: room.id,
         name: room.name,
         description: room.description,
         exits: list_exits(room_id),
         objects: list_objects_in_room(room_id),
         other_players: list_other_players(room_id, player_id)
       }}
    else
      {:error, :no_current_room} = err -> err
      nil -> {:error, :room_missing}
    end
  end

  @spec list_inventory(integer()) :: [
          %{id: String.t(), name: String.t(), short_description: String.t()}
        ]
  def list_inventory(player_id) when is_integer(player_id) do
    from(o in Object,
      where: o.player_id == ^player_id,
      order_by: o.name,
      select: %{id: o.id, name: o.name, short_description: o.short_description}
    )
    |> Repo.all()
  end

  @doc """
  Resolve an object name within a room's current contents to its object_id.
  Case-insensitive; whitespace-collapsed. Returns `:ambiguous` if more than
  one object in the room matches.
  """
  @spec resolve_object_in_room(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :no_such_object | :ambiguous}
  def resolve_object_in_room(room_id, name) when is_binary(room_id) and is_binary(name) do
    needle = normalize_name(name)

    rows =
      from(o in Object,
        where: o.room_id == ^room_id,
        select: %{id: o.id, name: o.name}
      )
      |> Repo.all()

    case Enum.filter(rows, fn r -> normalize_name(r.name) == needle end) do
      [] -> {:error, :no_such_object}
      [%{id: id}] -> {:ok, id}
      _multiple -> {:error, :ambiguous}
    end
  end

  @doc """
  Resolve an object name within a player's inventory to its object_id.
  """
  @spec resolve_object_in_inventory(integer(), String.t()) ::
          {:ok, String.t()} | {:error, :no_such_object | :ambiguous}
  def resolve_object_in_inventory(player_id, name)
      when is_integer(player_id) and is_binary(name) do
    needle = normalize_name(name)

    rows =
      from(o in Object,
        where: o.player_id == ^player_id,
        select: %{id: o.id, name: o.name}
      )
      |> Repo.all()

    case Enum.filter(rows, fn r -> normalize_name(r.name) == needle end) do
      [] -> {:error, :no_such_object}
      [%{id: id}] -> {:ok, id}
      _multiple -> {:error, :ambiguous}
    end
  end

  @doc """
  Read the `fixed` flag for an object. Used by `World.Commands.take` to
  refuse fixed objects at the pre-dispatch layer (FR-010).
  """
  @spec object_fixed?(String.t()) :: {:ok, boolean()} | {:error, :no_such_object}
  def object_fixed?(object_id) when is_binary(object_id) do
    case Repo.get(Object, object_id) do
      nil -> {:error, :no_such_object}
      %Object{fixed: fixed} -> {:ok, fixed}
    end
  end

  defp list_exits(room_id) do
    from(e in Exit,
      join: t in Room,
      on: t.id == e.target_room_id,
      where: e.source_room_id == ^room_id,
      order_by: e.direction,
      select: %{direction: e.direction, target_name: t.name}
    )
    |> Repo.all()
  end

  defp list_objects_in_room(room_id) do
    from(o in Object,
      where: o.room_id == ^room_id,
      order_by: o.name,
      select: %{id: o.id, name: o.name, short_description: o.short_description}
    )
    |> Repo.all()
  end

  @doc """
  All players currently in `room_id` except `self_player_id`. Drives the
  Present HUD card and the `other_players` list in `look_room/1`.
  """
  @spec other_occupants_of(String.t(), integer()) :: [%{id: integer(), username: String.t()}]
  def other_occupants_of(room_id, self_player_id)
      when is_binary(room_id) and is_integer(self_player_id) do
    list_other_players(room_id, self_player_id)
  end

  defp list_other_players(room_id, self_player_id) do
    from(ps in PlayerState,
      join: p in AccountPlayer,
      on: p.id == ps.player_id,
      where: ps.current_room_id == ^room_id and ps.player_id != ^self_player_id,
      order_by: p.username,
      select: %{id: p.id, username: p.username}
    )
    |> Repo.all()
  end

  defp normalize_name(s) do
    s
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join(" ")
  end
end
