defmodule AgenticRealms.World.Entity do
  @moduledoc """
  Generic world-entity aggregate (feature 016). Owns an entity's existence,
  its `kind` (`:object | :npc`), and its current `container` — modeled on the
  `Player` aggregate, which already owns its own location.

  Identified by `:entity_id` with prefix `"entity-"`. Handles:

    * `CloneEntity` — born in the void (`EntityCloned`). Re-clone → `:already_exists`.
    * `MoveEntity`  — relocate (`EntityMoved`). No-op when `to` == current; rejects a
      stale `expected_from` with `:container_conflict` (FR-005, preserves take/drop
      "already taken" under concurrency); unknown destination type → `:unsupported_container`.
    * `EditEntity` — sparse in-place field edit (`EntityEdited`); no-op diff → no event.

  The aggregate validates *type* and *self-consistency* only; it cannot verify
  the destination container *exists* (cross-aggregate) — that is the world
  service's job (`AgenticRealms.World.Commands.move_entity/4`).

  See `specs/016-entity-containment/{data-model,contracts}`.
  """

  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity, EditEntity}
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityEdited}

  @kinds ~w(object npc)a

  defstruct id: nil, kind: nil, container: nil

  # --- CloneEntity --------------------------------------------------------

  @spec execute(%__MODULE__{}, %CloneEntity{} | %MoveEntity{} | %EditEntity{}) ::
          %EntityCloned{} | %EntityMoved{} | %EntityEdited{} | :ok | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CloneEntity{
        entity_id: id,
        kind: kind,
        fields: fields
      }) do
    case normalize_kind(kind) do
      nil -> {:error, :unsupported_kind}
      k -> %EntityCloned{entity_id: id, kind: k, fields: fields}
    end
  end

  def execute(%__MODULE__{}, %CloneEntity{}), do: {:error, :already_exists}

  # --- MoveEntity ---------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %MoveEntity{}), do: {:error, :not_found}

  def execute(%__MODULE__{container: container}, %MoveEntity{
        entity_id: id,
        expected_from: expected_from,
        to: to,
        cause: cause
      }) do
    to = ContainerRef.from_map(to)

    cond do
      not ContainerRef.valid_type?(to.type) ->
        {:error, :unsupported_container}

      ContainerRef.equal?(to, container) ->
        # No-op move (FR-009) — already in the destination.
        :ok

      not ContainerRef.equal?(expected_from, container) ->
        # Stale / concurrent origin — refuse rather than steal (FR-005).
        {:error, :container_conflict}

      true ->
        %EntityMoved{entity_id: id, from: container, to: to, cause: cause}
    end
  end

  # --- EditEntity ---------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %EditEntity{}), do: {:error, :not_found}

  def execute(%__MODULE__{}, %EditEntity{entity_id: id, fields_changed: changed}) do
    if changed == %{} or map_size(changed) == 0 do
      :ok
    else
      %EntityEdited{entity_id: id, fields_changed: changed}
    end
  end

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %EntityCloned{} | %EntityMoved{} | %EntityEdited{}) ::
          %__MODULE__{}
  def apply(%__MODULE__{} = state, %EntityCloned{entity_id: id, kind: kind}) do
    %__MODULE__{state | id: id, kind: normalize_kind(kind), container: ContainerRef.void()}
  end

  def apply(%__MODULE__{} = state, %EntityMoved{to: to}) do
    %__MODULE__{state | container: ContainerRef.from_map(to)}
  end

  # Field edits live in the read model, not the aggregate.
  def apply(%__MODULE__{} = state, %EntityEdited{}), do: state

  # --- helpers ------------------------------------------------------------

  defp normalize_kind(kind) when kind in @kinds, do: kind
  defp normalize_kind("object"), do: :object
  defp normalize_kind("npc"), do: :npc
  defp normalize_kind(_), do: nil
end

# Snapshot serialization (mirrors the Player aggregate): `container` is a
# `ContainerRef` struct → render as its map form on encode, rebuild on decode.
defimpl Jason.Encoder, for: AgenticRealms.World.Entity do
  def encode(%AgenticRealms.World.Entity{container: container} = entity, opts) do
    container_map = container && AgenticRealms.World.ContainerRef.to_map(container)

    entity
    |> Map.from_struct()
    |> Map.put(:container, container_map)
    |> Jason.Encode.map(opts)
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: AgenticRealms.World.Entity do
  def decode(%AgenticRealms.World.Entity{container: container} = state)
      when is_map(container) and not is_struct(container) do
    %{state | container: AgenticRealms.World.ContainerRef.from_map(container)}
  end

  def decode(%AgenticRealms.World.Entity{} = state), do: state
end
