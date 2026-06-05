defmodule AgenticRealms.World.Room do
  @moduledoc """
  Room aggregate. Owns a room's display info (name + description), its exit
  set, and map metadata.

  **Feature 016 note**: object presence (`object_ids`) and the object
  spawn / place / take / drop / edit command+event handling were removed
  from this aggregate when the entity lifecycle moved to `World.Entity`
  (clone/move). Objects are now freestanding entities whose container is a
  property of the entity, not of the room. Occupancy and object location
  both live in read models, not on this aggregate.

  See `specs/003-persisted-world/data-model.md` §1.1 and
  `specs/016-entity-containment/data-model.md`.
  """

  defstruct id: nil,
            name: nil,
            description: nil,
            exits: %{},
            behaviors: [],
            # Feature 012 — Maps
            region_id: nil,
            map_visible: true,
            elevation: 0,
            map_x: nil,
            map_y: nil

  alias AgenticRealms.World.Commands.{CreateRoom, AddExit}
  alias AgenticRealms.World.Events.{RoomCreated, ExitAdded}

  # --- CreateRoom ---------------------------------------------------------

  @spec execute(%__MODULE__{}, %CreateRoom{} | %AddExit{}) ::
          %RoomCreated{} | %ExitAdded{} | :ok | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CreateRoom{
        room_id: id,
        name: name,
        description: description,
        behaviors: behaviors,
        region_id: region_id,
        map_visible: map_visible,
        elevation: elevation,
        map_x: map_x,
        map_y: map_y
      }) do
    %RoomCreated{
      room_id: id,
      name: name,
      description: description,
      behaviors: behaviors,
      region_id: region_id,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
    }
  end

  def execute(%__MODULE__{}, %CreateRoom{}), do: {:error, :room_already_exists}

  # --- AddExit ------------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %AddExit{}), do: {:error, :room_not_found}

  def execute(%__MODULE__{id: id, exits: exits}, %AddExit{
        room_id: id,
        direction: direction,
        target_room_id: target
      })
      when not is_nil(target) do
    if Map.has_key?(exits, direction) do
      {:error, :exit_already_exists}
    else
      %ExitAdded{room_id: id, direction: direction, target_room_id: target}
    end
  end

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %RoomCreated{} | %ExitAdded{}) :: %__MODULE__{}
  def apply(
        %__MODULE__{} = state,
        %RoomCreated{
          room_id: id,
          name: name,
          description: description,
          behaviors: behaviors
        } = event
      ) do
    %__MODULE__{
      state
      | id: id,
        name: name,
        description: description,
        behaviors: behaviors,
        region_id: Map.get(event, :region_id),
        map_visible: Map.get(event, :map_visible, true),
        elevation: Map.get(event, :elevation, 0),
        map_x: Map.get(event, :map_x),
        map_y: Map.get(event, :map_y)
    }
  end

  def apply(%__MODULE__{exits: exits} = state, %ExitAdded{
        direction: direction,
        target_room_id: target
      }) do
    %__MODULE__{state | exits: Map.put(exits, direction, target)}
  end
end

# Snapshot serialization for the Room aggregate (issue #6). `exits` keys are
# string directions; the Jason :atoms key strategy atomizes them on decode,
# so we re-stringify to keep `Map.has_key?(exits, "north")` working.
defimpl Jason.Encoder, for: AgenticRealms.World.Room do
  def encode(%AgenticRealms.World.Room{} = room, opts) do
    room
    |> Map.from_struct()
    |> Jason.Encode.map(opts)
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: AgenticRealms.World.Room do
  def decode(%AgenticRealms.World.Room{exits: exits} = state) do
    %{state | exits: stringify_keys(exits)}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
