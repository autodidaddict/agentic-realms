defmodule AgenticRealms.World.Entity do
  @moduledoc """
  Generic world-entity aggregate. Owns an entity's existence,
  its `kind` (`:object | :npc`), and its current `container` — modeled on the
  `Player` aggregate, which already owns its own location.

  Identified by `:entity_id` with prefix `"entity-"`. Handles:

    * `CloneEntity` — born in the void (`EntityCloned`). Re-clone → `:already_exists`.
    * `MoveEntity`  — relocate (`EntityMoved`). No-op when `to` == current; rejects a
      stale `expected_from` with `:container_conflict` (preserves take/drop
      "already taken" under concurrency); unknown destination type → `:unsupported_container`.
    * `EditEntity` — sparse in-place field edit (`EntityEdited`); no-op diff → no event.

  The aggregate validates *type* and *self-consistency* only; it cannot verify
  the destination container *exists* (cross-aggregate) — that is the world
  service's job (`AgenticRealms.World.Commands.move_entity/4`).
  """

  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity, EditEntity, RemoveEntity}
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityEdited, EntityRemoved}

  @kinds ~w(object npc)a

  defstruct id: nil, kind: nil, container: nil, name: nil, removed: false

  @spec execute(%__MODULE__{}, %CloneEntity{} | %MoveEntity{} | %EditEntity{} | %RemoveEntity{}) ::
          %EntityCloned{}
          | %EntityMoved{}
          | %EntityEdited{}
          | %EntityRemoved{}
          | :ok
          | {:error, atom()}
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

  def execute(%__MODULE__{id: nil}, %MoveEntity{}), do: {:error, :not_found}

  def execute(%__MODULE__{kind: kind, container: container}, %MoveEntity{
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
        :ok

      not ContainerRef.equal?(expected_from, container) ->
        {:error, :container_conflict}

      true ->
        %EntityMoved{entity_id: id, from: container, to: to, cause: cause, kind: kind}
    end
  end

  def execute(%__MODULE__{id: nil}, %EditEntity{}), do: {:error, :not_found}

  def execute(%__MODULE__{kind: kind}, %EditEntity{entity_id: id, fields_changed: changed}) do
    if changed == %{} or map_size(changed) == 0 do
      :ok
    else
      %EntityEdited{entity_id: id, fields_changed: changed, kind: kind}
    end
  end

  def execute(%__MODULE__{id: nil}, %RemoveEntity{}), do: {:error, :not_found}
  def execute(%__MODULE__{removed: true}, %RemoveEntity{}), do: {:error, :not_found}

  def execute(%__MODULE__{kind: kind, container: container, name: name}, %RemoveEntity{
        entity_id: id
      }) do
    %EntityRemoved{entity_id: id, kind: kind, from: container, name: name}
  end

  @spec apply(
          %__MODULE__{},
          %EntityCloned{} | %EntityMoved{} | %EntityEdited{} | %EntityRemoved{}
        ) ::
          %__MODULE__{}
  def apply(%__MODULE__{} = state, %EntityCloned{entity_id: id, kind: kind, fields: fields}) do
    %__MODULE__{
      state
      | id: id,
        kind: normalize_kind(kind),
        container: ContainerRef.void(),
        name: fetch_field(fields, :name)
    }
  end

  def apply(%__MODULE__{} = state, %EntityMoved{to: to}) do
    %__MODULE__{state | container: ContainerRef.from_map(to)}
  end

  def apply(%__MODULE__{} = state, %EntityEdited{}), do: state

  def apply(%__MODULE__{} = state, %EntityRemoved{}), do: %__MODULE__{state | removed: true}

  defp normalize_kind(kind) when kind in @kinds, do: kind
  defp normalize_kind("object"), do: :object
  defp normalize_kind("npc"), do: :npc
  defp normalize_kind(_), do: nil

  defp fetch_field(fields, key) when is_map(fields) do
    case Map.fetch(fields, key) do
      {:ok, v} -> v
      :error -> Map.get(fields, Atom.to_string(key))
    end
  end

  defp fetch_field(_fields, _key), do: nil
end

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
