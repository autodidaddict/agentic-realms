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

  alias AgenticRealms.World.Schemas.{
    Room,
    Exit,
    Object,
    Blueprint,
    PlayerState,
    NPCClone,
    PlayerDiscoveredRoom
  }

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
         # Feature 013 — viewer-aware object listing. Quest-scoped items
         # are visible only to their owning player.
         objects: list_objects_in_room_for_viewer(room_id, player_id),
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
    case Repo.get(Blueprint, blueprint_id) do
      %Blueprint{kind: "npc"} = bp ->
        {:ok,
         %{
           id: bp.id,
           name: bp.name,
           short_description: bp.short_description,
           long_description: bp.long_description
         }}

      _ ->
        {:error, :no_such_blueprint}
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
      where: o.container_type == "player" and o.container_id == ^Integer.to_string(player_id),
      order_by: o.name,
      select: %{id: o.id, name: o.name, short_description: o.short_description}
    )
    |> Repo.all()
  end

  @doc """
  Resolve an object name within a room's current contents to its object_id,
  filtered for the given viewer per feature 013's per-viewer item
  visibility (quest-scoped items are invisible to non-owners).

  Case-insensitive; whitespace-collapsed. Returns `:ambiguous` if more than
  one object in the room visible to this viewer matches.
  """
  @spec resolve_object_in_room(String.t(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, :no_such_object | :ambiguous}
  def resolve_object_in_room(room_id, viewer_player_id, name)
      when is_binary(room_id) and is_integer(viewer_player_id) and is_binary(name) do
    needle = normalize_name(name)

    rows =
      from(o in Object,
        where:
          o.container_type == "room" and o.container_id == ^room_id and
            (is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id),
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
        where: o.container_type == "player" and o.container_id == ^Integer.to_string(player_id),
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

  @doc """
  All objects currently in `room_id`, ordered alphabetically.

  **WARNING — unsafe for rendering as of feature 013.** This function does
  not honor quest-scoped item visibility (`quest_player_id`). Use
  `list_objects_in_room_for_viewer/2` for any path that renders objects
  to a specific player. Retained for tick-behavior scope assembly
  (`RoomTicks.Scope`), where every present object should participate
  regardless of quest scoping.
  """
  @spec list_objects_in_room(String.t()) :: [
          %{id: String.t(), name: String.t(), short_description: String.t()}
        ]
  def list_objects_in_room(room_id) when is_binary(room_id) do
    from(o in Object,
      where: o.container_type == "room" and o.container_id == ^room_id,
      order_by: o.name,
      select: %{id: o.id, name: o.name, short_description: o.short_description}
    )
    |> Repo.all()
  end

  @doc """
  Viewer-aware variant of `list_objects_in_room/1` (feature 013). Objects
  carrying a `quest_player_id` are visible only to the player whose id
  matches; objects without a `quest_player_id` are visible to everyone.

  Used by every room-rendering call path (`look_room/1`, the room-view
  composer, examine paths) to enforce per-player quest item visibility.
  """
  @spec list_objects_in_room_for_viewer(String.t(), integer()) :: [
          %{id: String.t(), name: String.t(), short_description: String.t()}
        ]
  def list_objects_in_room_for_viewer(room_id, viewer_player_id)
      when is_binary(room_id) and is_integer(viewer_player_id) do
    from(o in Object,
      where:
        o.container_type == "room" and o.container_id == ^room_id and
          (is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id),
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

  @doc """
  Returns the list of player ids whose `current_room_id == room_id` AND
  who appear in `Phoenix.Presence`'s online set (feature 011). Used by
  `RoomTicks.Scheduler` to compute fan-out recipients for tick-driven
  room/object speech, and by `RoomTicks.Lifecycle` to seed live-occupant
  state on Scheduler init.

  Returns ids only — no usernames — to keep this hot path cheap.
  """
  @spec live_occupants_of(String.t()) :: [integer()]
  def live_occupants_of(room_id) when is_binary(room_id) do
    online = online_player_ids()

    from(ps in PlayerState,
      where: ps.current_room_id == ^room_id,
      select: ps.player_id
    )
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(online, &1))
  end

  @doc """
  Returns all objects currently held by any player whose `current_room_id
  == room_id` (feature 011). Used by `RoomTicks.Scope` to include carried
  objects in the tick-behavior scope set for the carrier's current room.

  The caller is responsible for filtering by online presence if needed
  (the scheduler does this via the carrier's appearance in
  `live_occupants_of/1`).

  Returns the full Ecto `%Object{}` struct rows so callers can read the
  `behaviors` field directly.
  """
  @spec list_carried_objects_in_room(String.t()) :: [AgenticRealms.World.Schemas.Object.t()]
  def list_carried_objects_in_room(room_id) when is_binary(room_id) do
    from(o in Object,
      join: ps in PlayerState,
      on: fragment("?::text", ps.player_id) == o.container_id,
      where: ps.current_room_id == ^room_id and o.container_type == "player",
      select: o
    )
    |> Repo.all()
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

  # ------------------------------------------------------------------------
  # Feature 012 — Maps: read helpers for World.MapView
  # ------------------------------------------------------------------------
  #
  # Performance posture: these queries are called every time the player's
  # map needs to re-render (every move, every newly-discovered room). All
  # five are constant-or-bounded-work given:
  #   * `discovered_room_ids_for/1` — composite-PK index scan, no JOIN.
  #   * `rooms_in_region_at_elevation_within_viewport/4` — bounded to the
  #     viewport_cells² window via x/y BETWEEN clauses; uses the
  #     `(region_id, elevation)` btree index plus the partial unique index
  #     on `(region_id, elevation, map_x, map_y)`. Preloads exits + targets
  #     in one round-trip to avoid N+1 when MapView builds `has_up?` /
  #     `has_down?` flags and classifies exits.
  #   * `exits_for_rooms/1` — single IN-list query against the
  #     `(source_room_id, direction)` composite key.
  #   * `has_discovered_rooms_above?/3` / `has_discovered_rooms_below?/3` —
  #     EXISTS-style queries; Postgres short-circuits on the first match.

  @doc """
  Returns the set of room ids that `player_id` has personally discovered.
  Constant-time-per-row index scan against the composite PK.
  """
  @spec discovered_room_ids_for(integer()) :: MapSet.t()
  def discovered_room_ids_for(player_id) when is_integer(player_id) do
    from(d in PlayerDiscoveredRoom,
      where: d.player_id == ^player_id,
      select: d.room_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  All discovered, map-visible, coord-bearing rooms in the given region at
  the given elevation. The client-side pan/zoom logic owns the viewport
  decision — the server emits the full set and the SVG `viewBox` handles
  what's visible. Typical regions are ≤200 rooms so the over-fetch cost
  is negligible.
  """
  @spec rooms_in_region_at_elevation(String.t(), integer(), MapSet.t()) :: [%Room{}]
  def rooms_in_region_at_elevation(region_id, elevation, discovered_ids)
      when is_binary(region_id) and is_integer(elevation) do
    discovered_list = MapSet.to_list(discovered_ids)

    from(r in Room,
      where:
        r.region_id == ^region_id and
          r.elevation == ^elevation and
          r.map_visible == true and
          not is_nil(r.map_x) and
          not is_nil(r.map_y) and
          r.id in ^discovered_list
    )
    |> Repo.all()
  end

  @doc """
  All exits whose `source_room_id` is in the given list, with the target
  room preloaded enough for the MapView's classification step (just the
  fields the classifier reads: `id`, `region_id`, `map_visible`, `map_x`,
  `map_y`, `name`).
  """
  @spec exits_for_rooms([String.t()]) :: [%Exit{target_room: %Room{}}]
  def exits_for_rooms([]), do: []

  def exits_for_rooms(room_ids) when is_list(room_ids) do
    from(e in Exit,
      where: e.source_room_id in ^room_ids,
      join: t in Room,
      on: t.id == e.target_room_id,
      preload: [target_room: t]
    )
    |> Repo.all()
  end

  @doc """
  Whether the player has discovered ANY room in `region_id` at elevations
  strictly greater than `current_elevation`. Postgres short-circuits on
  the first match — sub-millisecond on realistic data.
  """
  @spec has_discovered_rooms_above?(String.t(), integer(), integer()) :: boolean()
  def has_discovered_rooms_above?(region_id, current_elevation, player_id) do
    Repo.exists?(
      from(r in Room,
        join: d in PlayerDiscoveredRoom,
        on: d.room_id == r.id and d.player_id == ^player_id,
        where: r.region_id == ^region_id and r.elevation > ^current_elevation
      )
    )
  end

  @doc """
  Mirror of `has_discovered_rooms_above?/3` for lower elevations.
  """
  @spec has_discovered_rooms_below?(String.t(), integer(), integer()) :: boolean()
  def has_discovered_rooms_below?(region_id, current_elevation, player_id) do
    Repo.exists?(
      from(r in Room,
        join: d in PlayerDiscoveredRoom,
        on: d.room_id == r.id and d.player_id == ^player_id,
        where: r.region_id == ^region_id and r.elevation < ^current_elevation
      )
    )
  end

  # ──────────────────────────────────────────────────────────────────────
  # Feature 014 — Object Blueprints
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Fetch a single Blueprint (any kind) by its slug id, as a full schema
  struct. Returns `nil` if no such row exists.
  """
  @spec get_blueprint(String.t()) :: %Blueprint{} | nil
  def get_blueprint(blueprint_id) when is_binary(blueprint_id) do
    Repo.get(Blueprint, blueprint_id)
  end

  @doc """
  Feature 015 — all Blueprint rows (both kinds) as full schema structs,
  ordered by name then id. Backs the wizard's unified registry pane.
  """
  @spec list_blueprint_rows() :: [%Blueprint{}]
  def list_blueprint_rows do
    Repo.all(from(b in Blueprint, order_by: [asc: b.name, asc: b.id]))
  end

  @doc """
  List all Object Blueprints, ordered by name (transitional helper —
  callers migrate to `list_blueprints/0,1`).
  """
  @spec list_object_blueprints() :: [%Blueprint{}]
  def list_object_blueprints do
    Repo.all(from(b in Blueprint, where: b.kind == "object", order_by: [asc: b.name, asc: b.id]))
  end

  @doc "Fetch a single object-kind Blueprint by slug id, or `nil`."
  @spec get_object_blueprint(String.t()) :: %Blueprint{} | nil
  def get_object_blueprint(blueprint_id) when is_binary(blueprint_id) do
    Repo.get_by(Blueprint, id: blueprint_id, kind: "object")
  end

  @doc "List all NPC Blueprints, ordered by name (transitional helper)."
  @spec list_npc_blueprints() :: [%Blueprint{}]
  def list_npc_blueprints do
    Repo.all(from(b in Blueprint, where: b.kind == "npc", order_by: [asc: b.name, asc: b.id]))
  end

  @doc "Fetch a single npc-kind Blueprint as a full schema struct, or `nil`."
  @spec get_npc_blueprint_row(String.t()) :: %Blueprint{} | nil
  def get_npc_blueprint_row(blueprint_id) when is_binary(blueprint_id) do
    Repo.get_by(Blueprint, id: blueprint_id, kind: "npc")
  end

  @registry_kinds ~w(object npc)

  @doc """
  Feature 015 US8 — unified blueprint registry (FR-024/FR-025). Projects the
  `blueprints` table to a uniform display row
  `%{id, kind, name, short_description, revision}`, ordered by name then id.
  """
  @spec list_blueprints() :: [map()]
  def list_blueprints do
    Repo.all(
      from(b in Blueprint,
        order_by: [asc: b.name, asc: b.id],
        select: %{
          id: b.id,
          kind: b.kind,
          name: b.name,
          short_description: b.short_description,
          revision: b.revision
        }
      )
    )
  end

  @doc "Unified registry filtered to one kind (`\"object\"` | `\"npc\"`)."
  @spec list_blueprints(String.t()) :: [map()]
  def list_blueprints(kind) when kind in @registry_kinds do
    Repo.all(
      from(b in Blueprint,
        where: b.kind == ^kind,
        order_by: [asc: b.name, asc: b.id],
        select: %{
          id: b.id,
          kind: b.kind,
          name: b.name,
          short_description: b.short_description,
          revision: b.revision
        }
      )
    )
  end

  @doc """
  Fetch a single Object by id. Returns `nil` if no such row exists.
  """
  @spec get_object(String.t()) :: %Object{} | nil
  def get_object(object_id) when is_binary(object_id) do
    Repo.get(Object, object_id)
  end

  @doc """
  Wizard-facing variant of `get_object/1` — returns `nil` for rows
  that are quest-scoped (carry a non-nil `quest_player_id`). Mirrors
  the filter that `list_objects_in_room_for_wizard/1` applies to the
  wizard's Things-in-this-room panel. Use this anywhere a wizard
  command/handler resolves an object_id by user input so that
  quest-scoped items (which belong to a specific player) cannot be
  extracted, edited, or otherwise manipulated by wizards in
  milestone 1.
  """
  @spec get_object_for_wizard(String.t()) :: %Object{} | nil
  def get_object_for_wizard(object_id) when is_binary(object_id) do
    case Repo.get(Object, object_id) do
      %Object{quest_player_id: nil} = obj -> obj
      _ -> nil
    end
  end

  @doc """
  Wizard-facing variant of `list_objects_in_room/1` — includes the
  `fixed` flag plus full descriptions so the Wizard view's
  Things-in-this-room panel and the Extract-essence action have what
  they need.

  Excludes quest-scoped items (rows with a `quest_player_id`) — wizards
  do not author / extract from per-player quest items in milestone 1.
  """
  @spec list_objects_in_room_for_wizard(String.t()) :: [
          %{
            id: String.t(),
            name: String.t(),
            short_description: String.t(),
            long_description: String.t(),
            fixed: boolean()
          }
        ]
  def list_objects_in_room_for_wizard(room_id) when is_binary(room_id) do
    from(o in Object,
      where:
        o.container_type == "room" and o.container_id == ^room_id and is_nil(o.quest_player_id),
      order_by: o.name,
      select: %{
        id: o.id,
        name: o.name,
        short_description: o.short_description,
        long_description: o.long_description,
        fixed: o.fixed
      }
    )
    |> Repo.all()
  end
end
