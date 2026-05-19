defmodule AgenticRealms.World.Projections.PlayerStateProjector do
  @moduledoc """
  Projects player lifecycle events into the `player_state` read model.

  Event handler clauses added so far:
    * Phase 4 (US1): PlayerSpawned → upsert player_state.current_room_id
    * Phase 5 (US2): PlayerMoved   → update player_state.current_room_id
                                     (with FR-022 nilify if target room gone)

  All upserts use `on_conflict: :replace_all` so replays are safe.
  """

  # `:strong` so callers can dispatch SpawnPlayer (and MovePlayer)
  # with `consistency: :strong` and be guaranteed that the `player_state`
  # row is in place by the time the dispatch returns. Without this the
  # LiveView's mount races the projector and crashes for new players.
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved}
  alias AgenticRealms.World.Schemas.{PlayerState, Room}

  def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
    now = utc_now()

    Repo.insert!(
      %PlayerState{
        player_id: pid,
        current_room_id: room_id,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [current_room_id: room_id, updated_at: now]],
      conflict_target: :player_id
    )

    :ok
  end

  def handle(%PlayerMoved{player_id: pid, to_room_id: to}, _meta) do
    # FR-022: if the destination room has been removed from the world
    # (e.g., the seed was reshaped), null out current_room_id so the
    # next Play visit triggers a fresh SpawnPlayer into the starter room.
    target =
      if room_exists?(to) do
        to
      else
        nil
      end

    now = utc_now()

    Repo.update_all(
      from(ps in PlayerState, where: ps.player_id == ^pid),
      set: [current_room_id: target, updated_at: now]
    )

    :ok
  end

  defp room_exists?(room_id) do
    Repo.exists?(from(r in Room, where: r.id == ^room_id))
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
