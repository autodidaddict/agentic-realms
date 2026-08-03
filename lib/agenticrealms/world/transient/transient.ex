defmodule AgenticRealms.World.Transient do
  @moduledoc """
  Transient Regions context. The programmatic provisioning
  surface (there is no player-facing command in the MVP): `provision/2`
  orchestrates the generate → guard → dispatch → place-owner flow, and
  `destroy/1` (added with the teardown lifecycle) force-destroys + purges a
  region now.

  Provisioning is a sequence of strongly-consistent dispatches so the read
  model (region row, rooms, exits, owner location) is fully populated before
  it returns — the owner can immediately see and traverse the owner-only
  `:rift` entry exit.
  """

  import Ecto.Query
  require Logger

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands, as: WorldCommands

  alias AgenticRealms.World.Commands.{
    ProvisionTransientRegion,
    OpenTransientEntryExit,
    AddExit,
    MovePlayer,
    DestroyRegion
  }

  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Region, Room, PlayerState}
  alias AgenticRealms.World.Transient.{Generator, Purge}

  @doc """
  Provision a transient region for `owner_id`, entered from `source_room_id`
  (which must be the owner's current room). Returns `{:ok, region_id}`.

  Refusals: `:owner_not_spawned`, `:owner_not_in_source_room`,
  `:already_provisioned` (one active transient region per owner),
  or any dispatch error.
  """
  @spec provision(integer(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def provision(owner_id, source_room_id)
      when is_integer(owner_id) and is_binary(source_room_id) do
    with :ok <- ensure_owner_in_source_room(owner_id, source_room_id),
         :ok <- ensure_not_already_provisioned(owner_id) do
      spec = Generator.generate(owner_id, source_room_id)
      provisioned_at = DateTime.utc_now()

      result =
        with :ok <- dispatch_provision(spec, provisioned_at),
             :ok <- create_rooms(spec),
             :ok <- add_intra_exits(spec),
             :ok <- open_entry_exit(spec),
             :ok <- place_owner(owner_id, spec) do
          :ok
        end

      case result do
        :ok ->
          Logger.info(
            "Transient region #{spec.region_id} provisioned for player #{owner_id} " <>
              "(#{length(spec.rooms)} rooms, source #{source_room_id})"
          )

          {:ok, spec.region_id}

        {:error, reason} ->
          Logger.warning(
            "Transient region #{spec.region_id} provisioning failed (#{inspect(reason)}); rolling back"
          )

          _ = destroy(spec.region_id)
          {:error, reason}
      end
    end
  end

  @doc """
  Force-destroy and purge a transient region now: relocate any occupants back
  to the source room, evict the aggregate (`DestroyRegion` → lifespan `:stop`),
  then hard-purge every stream + read-model row. Idempotent — a missing region
  returns `:ok`. Called by the reaper (`Transient.Manager`) and by ops/tests.
  """
  @spec destroy(String.t()) :: :ok
  def destroy(region_id) when is_binary(region_id) do
    case Repo.get(Region, region_id) do
      nil ->
        :ok

      %Region{} = region ->
        room_ids = Repo.all(from(r in Room, where: r.region_id == ^region_id, select: r.id))
        relocate_occupants(room_ids, region.source_room_id)
        WorldApp.dispatch(%DestroyRegion{region_id: region_id}, consistency: :strong)
        Purge.run(region_id)

        Logger.info(
          "Transient region #{region_id} (owner #{region.provision_owner_id}) destroyed and purged"
        )

        :ok
    end
  end

  defp relocate_occupants(_room_ids, nil), do: :ok
  defp relocate_occupants([], _source), do: :ok

  defp relocate_occupants(room_ids, source_room_id) do
    from(ps in PlayerState,
      where: ps.current_room_id in ^room_ids,
      select: %{player_id: ps.player_id, from: ps.current_room_id}
    )
    |> Repo.all()
    |> Enum.each(fn %{player_id: pid, from: from} ->
      WorldApp.dispatch(
        %MovePlayer{
          player_id: pid,
          from_room_id: from,
          to_room_id: source_room_id,
          direction: :rift
        },
        consistency: :strong
      )

      Phoenix.PubSub.broadcast(
        AgenticRealms.PubSub,
        AgenticRealmsWeb.Topics.player_topic(pid),
        :transient_region_ended
      )
    end)

    :ok
  end

  defp ensure_owner_in_source_room(owner_id, source_room_id) do
    case Queries.current_room_of(owner_id) do
      {:ok, ^source_room_id} -> :ok
      {:ok, _other} -> {:error, :owner_not_in_source_room}
      {:error, :no_current_room} -> {:error, :owner_not_spawned}
    end
  end

  defp ensure_not_already_provisioned(owner_id) do
    if Repo.exists?(
         from(r in Region,
           where:
             r.kind == "transient" and r.provision_owner_id == ^owner_id and
               is_nil(r.destroyed_at)
         )
       ) do
      {:error, :already_provisioned}
    else
      :ok
    end
  end

  defp dispatch_provision(spec, provisioned_at) do
    WorldApp.dispatch(
      %ProvisionTransientRegion{
        region_id: spec.region_id,
        name: spec.name,
        provision_owner_id: spec.provision_owner_id,
        provisioned_at: provisioned_at,
        source_room_id: spec.source_room_id,
        origin_room_id: spec.origin_room_id
      },
      consistency: :strong
    )
  end

  defp create_rooms(spec) do
    Enum.reduce_while(spec.rooms, :ok, fn room, :ok ->
      case WorldCommands.create_room(
             room.room_id,
             room.name,
             room.description,
             spec.region_id,
             map_visible: false
           ) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp add_intra_exits(spec) do
    Enum.reduce_while(spec.intra_exits, :ok, fn ex, :ok ->
      case WorldApp.dispatch(
             %AddExit{room_id: ex.from, direction: ex.direction, target_room_id: ex.to},
             consistency: :strong
           ) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp open_entry_exit(spec) do
    e = spec.entry_exit

    WorldApp.dispatch(
      %OpenTransientEntryExit{
        region_id: spec.region_id,
        source_room_id: e.source_room_id,
        direction: e.direction,
        origin_room_id: e.target_room_id,
        provision_owner_id: e.visible_to_user_id
      },
      consistency: :strong
    )
  end

  defp place_owner(owner_id, spec) do
    WorldApp.dispatch(
      %MovePlayer{
        player_id: owner_id,
        from_room_id: spec.source_room_id,
        to_room_id: spec.origin_room_id,
        direction: :rift
      },
      consistency: :strong
    )
  end
end
