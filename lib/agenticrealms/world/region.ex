defmodule AgenticRealms.World.Region do
  @moduledoc """
  Region aggregate. Owns the named map area to which one or more rooms
  belong. v1 supports creation only — no rename, no delete.

  See `specs/012-maps/data-model.md` §1.1 and
  `specs/012-maps/contracts/region.md`.
  """

  # Feature 017 — Transient Regions. `kind: :transient` regions carry an
  # owner + provisioning timestamp + the permanent source room and the
  # generated origin room; `destroyed?` guards idempotent teardown.
  defstruct id: nil,
            name: nil,
            kind: :permanent,
            provision_owner_id: nil,
            provisioned_at: nil,
            source_room_id: nil,
            origin_room_id: nil,
            destroyed?: false

  alias AgenticRealms.World.Commands.{
    CreateRegion,
    ProvisionTransientRegion,
    OpenTransientEntryExit,
    DestroyRegion
  }

  alias AgenticRealms.World.Events.{
    RegionCreated,
    TransientRegionProvisioned,
    TransientEntryExitOpened,
    RegionDestroyed
  }

  # --- CreateRegion -------------------------------------------------------

  @spec execute(
          %__MODULE__{},
          %CreateRegion{} | %ProvisionTransientRegion{} | %OpenTransientEntryExit{}
        ) ::
          %RegionCreated{}
          | %TransientRegionProvisioned{}
          | %TransientEntryExitOpened{}
          | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CreateRegion{region_id: id, name: name}) do
    case validate_name(name) do
      :ok -> %RegionCreated{region_id: id, name: name}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%__MODULE__{}, %CreateRegion{}), do: {:error, :region_already_exists}

  # --- ProvisionTransientRegion (feature 017) -----------------------------

  def execute(%__MODULE__{id: nil}, %ProvisionTransientRegion{
        region_id: id,
        name: name,
        provision_owner_id: owner,
        provisioned_at: at,
        source_room_id: src,
        origin_room_id: origin
      }) do
    case validate_name(name) do
      :ok ->
        %TransientRegionProvisioned{
          region_id: id,
          name: name,
          provision_owner_id: owner,
          provisioned_at: at,
          source_room_id: src,
          origin_room_id: origin
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(%__MODULE__{}, %ProvisionTransientRegion{}), do: {:error, :region_already_exists}

  # --- OpenTransientEntryExit (feature 017) -------------------------------

  def execute(%__MODULE__{id: nil}, %OpenTransientEntryExit{}), do: {:error, :region_not_found}

  def execute(%__MODULE__{kind: :transient}, %OpenTransientEntryExit{
        region_id: rid,
        source_room_id: src,
        direction: dir,
        origin_room_id: origin,
        provision_owner_id: owner
      }) do
    %TransientEntryExitOpened{
      region_id: rid,
      source_room_id: src,
      direction: dir,
      target_room_id: origin,
      visible_to_user_id: owner
    }
  end

  def execute(%__MODULE__{}, %OpenTransientEntryExit{}), do: {:error, :not_transient}

  # --- DestroyRegion (feature 017) ----------------------------------------
  # Idempotent: already-destroyed, or an already-purged (empty-stream) region,
  # is a no-op so the reaper can retry teardown safely.

  def execute(%__MODULE__{destroyed?: true}, %DestroyRegion{}), do: :ok
  def execute(%__MODULE__{id: nil}, %DestroyRegion{}), do: :ok

  def execute(%__MODULE__{}, %DestroyRegion{region_id: id}) do
    %RegionDestroyed{region_id: id}
  end

  # --- apply/2 ------------------------------------------------------------

  @spec apply(
          %__MODULE__{},
          %RegionCreated{} | %TransientRegionProvisioned{} | %TransientEntryExitOpened{}
        ) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %RegionCreated{region_id: id, name: name}) do
    %__MODULE__{state | id: id, name: name}
  end

  def apply(%__MODULE__{} = state, %TransientRegionProvisioned{
        region_id: id,
        name: name,
        provision_owner_id: owner,
        provisioned_at: at,
        source_room_id: src,
        origin_room_id: origin
      }) do
    %__MODULE__{
      state
      | id: id,
        name: name,
        kind: :transient,
        provision_owner_id: owner,
        provisioned_at: at,
        source_room_id: src,
        origin_room_id: origin
    }
  end

  # The entry exit lives in the read model; the aggregate records nothing
  # beyond having emitted it.
  def apply(%__MODULE__{} = state, %TransientEntryExitOpened{}), do: state

  def apply(%__MODULE__{} = state, %RegionDestroyed{}), do: %__MODULE__{state | destroyed?: true}

  # ------------------------------------------------------------------------

  defp validate_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :region_name_blank}
      _ -> :ok
    end
  end

  defp validate_name(_), do: {:error, :region_name_not_a_string}
end
