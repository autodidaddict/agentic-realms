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
  alias AgenticRealms.World.Schemas.{Room, Exit, Object, PlayerState, NPCBlueprint, NPCClone}
  alias AgenticRealmsWeb.Presence

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
         other_players: list_other_players(room_id, player_id),
         npcs: list_npcs_in_room(room_id)
       }}
    else
      {:error, :no_current_room} = err -> err
      nil -> {:error, :room_missing}
    end
  end

  @doc """
  All NPC clones currently located in `room_id`, ordered alphabetically by
  display name. Returns each clone's id, name, and short description — the
  room view does NOT need long descriptions (FR-005 in feature 007). Clone
  data is fully denormalized, so no join to the blueprint is needed.
  """
  @spec list_npcs_in_room(String.t()) ::
          [%{id: String.t(), name: String.t(), short_description: String.t()}]
  def list_npcs_in_room(room_id) when is_binary(room_id) do
    from(c in NPCClone,
      where: c.room_id == ^room_id,
      order_by: c.name,
      select: %{id: c.id, name: c.name, short_description: c.short_description}
    )
    |> Repo.all()
  end

  @doc """
  Fetch the behaviors list attached to a room (feature 009).

  Returns `{:ok, behaviors_list}` (which may be `[]`) or
  `{:error, :no_such_room}` if the room id is unknown.
  """
  @spec get_room_behaviors(String.t()) ::
          {:ok, [map()]} | {:error, :no_such_room}
  def get_room_behaviors(room_id) when is_binary(room_id) do
    case Repo.get(Room, room_id) do
      nil -> {:error, :no_such_room}
      %Room{behaviors: behaviors} -> {:ok, behaviors || []}
    end
  end

  @doc """
  List NPC clones in a room together with their behaviors list, ordered by
  the per-blueprint serial counter (feature 009). Returns an empty list
  when the room contains no NPCs.
  """
  @spec list_npc_clones_in_room_with_behaviors(String.t()) :: [
          %{
            id: String.t(),
            name: String.t(),
            serial: integer(),
            behaviors: [map()]
          }
        ]
  def list_npc_clones_in_room_with_behaviors(room_id) when is_binary(room_id) do
    from(c in NPCClone,
      where: c.room_id == ^room_id,
      order_by: c.serial,
      select: %{
        id: c.id,
        name: c.name,
        serial: c.serial,
        behaviors: c.behaviors
      }
    )
    |> Repo.all()
  end

  @doc """
  Fetch a single NPC blueprint by its stable identifier. Used by the
  pre-dispatch wrapper `Commands.spawn_npc_clone/3` to validate blueprint
  existence before dispatching the spawn command.
  """
  @spec get_npc_blueprint(String.t()) ::
          {:ok,
           %{
             id: String.t(),
             name: String.t(),
             short_description: String.t(),
             long_description: String.t()
           }}
          | {:error, :no_such_blueprint}
  def get_npc_blueprint(blueprint_id) when is_binary(blueprint_id) do
    case Repo.get(NPCBlueprint, blueprint_id) do
      nil ->
        {:error, :no_such_blueprint}

      %NPCBlueprint{} = bp ->
        {:ok,
         %{
           id: bp.id,
           name: bp.name,
           short_description: bp.short_description,
           long_description: bp.long_description
         }}
    end
  end

  @doc """
  Fetch a single NPC clone by its stable identifier. Used by the
  pre-dispatch wrapper to re-query the freshly-projected clone and return
  the assigned serial to the caller.
  """
  @spec get_npc_clone(String.t()) ::
          {:ok,
           %{
             id: String.t(),
             blueprint_id: String.t(),
             serial: integer(),
             name: String.t(),
             room_id: String.t()
           }}
          | {:error, :no_such_clone}
  def get_npc_clone(clone_id) when is_binary(clone_id) do
    case Repo.get(NPCClone, clone_id) do
      nil ->
        {:error, :no_such_clone}

      %NPCClone{} = c ->
        {:ok,
         %{
           id: c.id,
           blueprint_id: c.blueprint_id,
           serial: c.serial,
           name: c.name,
           room_id: c.room_id
         }}
    end
  end

  @doc """
  Find a clone in a given room by its display name (case-insensitive,
  whitespace-normalized). Used by the pre-dispatch per-room name-collision
  check (preserves feature 007 FR-001a at the clone level).
  """
  @spec find_clone_in_room_by_name(String.t(), String.t()) ::
          {:ok, %{id: String.t(), name: String.t()}}
          | {:error, :no_such_clone}
  def find_clone_in_room_by_name(room_id, name)
      when is_binary(room_id) and is_binary(name) do
    needle = normalize_name(name)

    rows =
      from(c in NPCClone,
        where: c.room_id == ^room_id,
        select: %{id: c.id, name: c.name}
      )
      |> Repo.all()

    case Enum.find(rows, fn r -> normalize_name(r.name) == needle end) do
      nil -> {:error, :no_such_clone}
      found -> {:ok, found}
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
  Resolve an NPC display name within a room's current contents to its npc_id.
  Mirrors `resolve_object_in_room/2`. Used by `World.Commands.take/2` to
  refuse takes against NPCs via the existing fixed-object refusal path
  (feature 007 FR-015).
  """
  @spec resolve_npc_in_room(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :no_such_npc | :ambiguous}
  def resolve_npc_in_room(room_id, name) when is_binary(room_id) and is_binary(name) do
    needle = normalize_name(name)

    rows =
      from(c in NPCClone,
        where: c.room_id == ^room_id,
        select: %{id: c.id, name: c.name}
      )
      |> Repo.all()

    case Enum.filter(rows, fn r -> normalize_name(r.name) == needle end) do
      [] -> {:error, :no_such_npc}
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
    rows =
      from(ps in PlayerState,
        join: p in AccountPlayer,
        on: p.id == ps.player_id,
        where: ps.current_room_id == ^room_id and ps.player_id != ^self_player_id,
        order_by: p.username,
        select: %{id: p.id, username: p.username}
      )
      |> Repo.all()

    # Filter by online presence: a player's persisted current_room_id remains
    # set after they log out (per the 003 design — disconnect does not unspawn
    # them), but offline players MUST NOT appear in the Present HUD card, in
    # `look` output, or as a valid `whisper` target. Authoritative truth for
    # "online" is `Phoenix.Presence`, which tracks every connected LiveView
    # session and deduplicates across multi-tab.
    online = online_player_ids()
    Enum.filter(rows, fn %{id: id} -> MapSet.member?(online, id) end)
  end

  defp online_player_ids do
    Presence.list(Presence.topic())
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
    |> MapSet.new()
  end

  defp normalize_name(s) do
    s
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join(" ")
  end
end
