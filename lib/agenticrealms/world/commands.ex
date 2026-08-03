defmodule AgenticRealms.World.Commands do
  @moduledoc """
  Write-side facade for the world. Wraps Commanded dispatches with pre-dispatch
  read-model validation, so a caller deals with one set of
  `{:ok, ...} | {:error, atom}` shapes rather than with aggregates.

  This module had grown to 1,573 lines and 33 public functions covering every
  bounded concern the world has. It is now the front door, and the concerns
  live behind it:

    * `Commands.Entities`  — the entity lifecycle (feature 016), plus `take`
                             and `drop`
    * `Commands.Authoring` — what a wizard authors and spawns: blueprints,
                             freeform spawns, essence extraction, in-world
                             edits (features 008, 014, 015)
    * `Commands.Quests`    — accept, progress, finalize (feature 013)
    * `Commands.Regions`   — regions, rooms, exits (feature 012)

  What stays here is the player themselves: spawning into the world, moving
  through it, creating a character, earning experience, and recording a room as
  discovered.

  Every function those modules own is still reachable through this one, so no
  caller changed. Reach for the specific module when adding to a concern;
  reach for this one when you do not know where something lives.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp

  alias AgenticRealms.World.CharacterDraft
  alias AgenticRealms.World.CharacterGen

  alias AgenticRealms.World.Commands.{
    AwardXp,
    CreateCharacter,
    MovePlayer,
    RecordRoomDiscovery,
    SpawnPlayer
  }

  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.PlayerNames
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Exit, PlayerState}

  @doc """
  Spawn a player into the starting room if (and only if) they have no
  current room yet. Idempotent for already-spawned players.
  """
  @spec spawn(integer(), String.t()) ::
          {:ok, :spawned | :already_spawned} | {:error, term()}
  def spawn(player_id, starting_room_id)
      when is_integer(player_id) and is_binary(starting_room_id) do
    case Queries.current_room_of(player_id) do
      {:ok, _room_id} ->
        {:ok, :already_spawned}

      {:error, :no_current_room} ->
        case WorldApp.dispatch(
               %SpawnPlayer{
                 player_id: player_id,
                 starting_room_id: starting_room_id
               },
               consistency: :strong
             ) do
          :ok -> {:ok, :spawned}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Create a player's character from the choices they made (feature 021).

  Three steps:

  1. **Complete** the draft. A draft only carries the choices a shipped user
     story asked for, so while later stories are unshipped it arrives without
     ability scores, skill picks, or a lineage. `CharacterGen.complete/1` fills
     exactly what the player was not asked, from the same options the rules
     package offers. This is what lets a story ship on its own; without it
     nothing could be created until every step of the dialog existed.
  2. **Validate** the completed draft. Every rule is unconditional because the
     validator only ever sees a whole character. Generated fills come from the
     offered options, so they cannot fail — every error a player sees is about
     something they entered.
  3. **Create** the character, `:strong`, so `player_state` carries it before
     the caller enters the world and reads the sheet.

  ## Names are checked, not reserved

  Between the availability check and the projection there is a window in which
  two players confirming the same name both succeed. The window is milliseconds
  wide and the consequence is cosmetic — two characters share a name, and
  addressing one by name is ambiguous until somebody renames.

  Closing it needs something atomic across the cluster, and the two ways to get
  that both cost more than the problem. A uniqueness aggregate turns creation
  into a two-phase commit with a compensating command and a claim that can
  outlive a dying node. A unique index needs a reservation table written outside
  a projector. Neither is worth carrying to prevent a rare cosmetic collision,
  so this checks and moves on.
  """
  @spec create_character(integer(), CharacterDraft.t()) ::
          {:ok, :created}
          | {:error, :name_taken}
          | {:error, [{atom(), String.t()}]}
          | {:error, term()}
  def create_character(player_id, %CharacterDraft{} = draft) when is_integer(player_id) do
    complete = CharacterGen.complete(draft)

    with :ok <- CharacterDraft.Validator.validate(complete),
         :ok <- name_available(complete.name),
         :ok <- create(player_id, complete) do
      {:ok, :created}
    end
  end

  defp name_available(name) do
    if PlayerNames.taken?(name), do: {:error, :name_taken}, else: :ok
  end

  defp create(player_id, draft) do
    command =
      draft
      |> CharacterGen.payload()
      |> Map.put(:player_id, player_id)
      |> then(&struct!(CreateCharacter, &1))

    WorldApp.dispatch(command, consistency: :strong)
  end

  @doc """
  Whether a player already has a character.

  What `GameLive` mounts on: no character means the creation dialog rather than
  the world.
  """
  @spec has_character?(integer()) :: boolean()
  def has_character?(player_id) when is_integer(player_id) do
    Repo.exists?(
      from(ps in PlayerState,
        where: ps.player_id == ^player_id and not is_nil(ps.species_slug)
      )
    )
  end

  @doc """
  Award experience to a player (feature 019). Players only; idempotent per
  `award_id` (a redelivered/replayed source event cannot double-award).
  Dispatched `:strong` so the `player_state` read model reflects the new
  xp/level before this returns.
  """
  @spec award_xp(integer(), pos_integer(), String.t()) :: :ok | {:error, term()}
  def award_xp(player_id, amount, award_id)
      when is_integer(player_id) and is_integer(amount) and is_binary(award_id) do
    WorldApp.dispatch(
      %AwardXp{
        player_id: player_id,
        amount: amount,
        award_id: award_id,
        source: award_id
      },
      consistency: :strong
    )
  end

  @doc """
  Move the player one step in the given direction.

  Returns `{:ok, to_room_id}` on success; `{:error, :no_exit_in_direction}`
  when the player's current room has no exit in that direction (FR-007);
  `{:error, :no_current_room}` if the player has never spawned.
  """
  @spec move(integer(), atom()) ::
          {:ok, String.t()}
          | {:error, :no_current_room | :no_exit_in_direction | term()}
  def move(player_id, direction)
      when is_integer(player_id) and is_atom(direction) do
    with {:ok, from_room_id} <- Queries.current_room_of(player_id),
         {:ok, to_room_id} <- resolve_exit(from_room_id, direction, player_id) do
      case WorldApp.dispatch(
             %MovePlayer{
               player_id: player_id,
               from_room_id: from_room_id,
               to_room_id: to_room_id,
               direction: direction
             },
             consistency: :strong
           ) do
        :ok -> {:ok, to_room_id}
        {:error, _} = err -> err
      end
    end
  end

  defdelegate clone_entity(kind, fields), to: __MODULE__.Entities
  defdelegate clone_entity(kind, entity_id, fields), to: __MODULE__.Entities
  defdelegate move_entity(entity_id, expected_from, to, cause), to: __MODULE__.Entities
  defdelegate remove_entity(entity_id), to: __MODULE__.Entities
  defdelegate remove_npc(npc_id), to: __MODULE__.Entities
  defdelegate clone_into(kind, fields, to, cause), to: __MODULE__.Entities
  defdelegate clone_into(kind, entity_id, fields, to, cause), to: __MODULE__.Entities
  defdelegate take(player_id, name), to: __MODULE__.Entities
  defdelegate drop(player_id, name), to: __MODULE__.Entities

  defp resolve_exit(from_room_id, direction, viewer_player_id) do
    dir_str = Direction.to_string(direction)

    case Repo.one(
           from(e in Exit,
             where:
               e.source_room_id == ^from_room_id and e.direction == ^dir_str and
                 (is_nil(e.visible_to_user_id) or e.visible_to_user_id == ^viewer_player_id),
             select: e.target_room_id
           )
         ) do
      nil -> {:error, :no_exit_in_direction}
      target -> {:ok, target}
    end
  end

  defdelegate create_region(region_id, name), to: __MODULE__.Regions

  defdelegate create_room(room_id, name, description, region_id, opts \\ []),
    to: __MODULE__.Regions

  defdelegate add_exit(source_room_id, direction, target_room_id), to: __MODULE__.Regions

  @doc """
  Dispatches a `RecordRoomDiscovery` command to the World.Player aggregate.
  The aggregate decides whether to emit a `PlayerDiscoveredRoom` event
  (only on first discovery for that room) — the caller MUST NOT pre-check
  the read model.

  This is the ONLY supported way to add a row to `player_discovered_rooms`.
  Direct Repo inserts to that table are forbidden by the project's event-
  sourcing invariant.

  **Eventual consistency.** This dispatch is called from inside the
  `PlayerStateProjector` event handler; a `consistency: :strong` dispatch
  would deadlock waiting for the same projector to acknowledge the
  resulting `PlayerDiscoveredRoom` event. The map's first render after
  spawn may briefly precede the discovery-row projection — that race is
  benign (the renderer just won't draw the room until the next refresh,
  which happens on the next move and on any subsequent UI event).
  """
  @spec record_room_discovery(integer(), String.t()) :: :ok | {:error, term()}
  def record_room_discovery(player_id, room_id)
      when is_integer(player_id) and is_binary(room_id) do
    WorldApp.dispatch(%RecordRoomDiscovery{player_id: player_id, room_id: room_id})
  end

  defdelegate accept_quest(player_id, npc_blueprint_id, slug), to: __MODULE__.Quests
  defdelegate check_progress(player_id, quest_id), to: __MODULE__.Quests
  defdelegate finalize_quest(player_id, quest_id), to: __MODULE__.Quests

  defdelegate spawn_npc_clone(blueprint_id, room_id, clone_id), to: __MODULE__.Authoring
  defdelegate create_blueprint(attrs, opts \\ []), to: __MODULE__.Authoring
  defdelegate create_object_blueprint(attrs, opts \\ []), to: __MODULE__.Authoring
  defdelegate create_npc_blueprint(attrs, opts \\ []), to: __MODULE__.Authoring
  defdelegate spawn_from_blueprint(wizard_id, blueprint_id, room_id), to: __MODULE__.Authoring

  defdelegate spawn_object_from_blueprint(wizard_id, blueprint_id, room_id),
    to: __MODULE__.Authoring

  defdelegate spawn_object_freeform(wizard_id, room_id, attrs), to: __MODULE__.Authoring
  defdelegate spawn_npc_freeform(wizard_id, room_id, attrs), to: __MODULE__.Authoring
  defdelegate extract_essence(wizard_id, entity_id, proposed_slug), to: __MODULE__.Authoring
  defdelegate edit_object_blueprint(wizard_id, blueprint_id, params), to: __MODULE__.Authoring
  defdelegate edit_object(wizard_id, object_id, fields_changed), to: __MODULE__.Authoring
  defdelegate edit_npc(wizard_id, clone_id, fields_changed), to: __MODULE__.Authoring
end
