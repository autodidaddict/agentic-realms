defmodule AgenticRealms.World.Transient.Generator do
  @moduledoc """
  Feature 017 — stand-in for a procedural region generator. For the MVP this
  hand-codes a small, fixed layout of interconnected rooms suitable for
  testing; there is no map data or real procedural generation yet.

  `generate/2` is pure: it mints fresh ids and returns a spec map describing
  the region, its rooms, the intra-region (+ return) exits, and the
  owner-only `:rift` entry exit. The caller (`Transient.provision/2`)
  dispatches the corresponding commands. Rooms are off-map (`map_visible:
  false`, nil coords) so they never appear on the mini-map.
  """

  @type spec :: %{
          region_id: String.t(),
          name: String.t(),
          provision_owner_id: integer(),
          source_room_id: String.t(),
          origin_room_id: String.t(),
          rooms: [%{room_id: String.t(), name: String.t(), description: String.t()}],
          intra_exits: [%{from: String.t(), direction: atom(), to: String.t()}],
          entry_exit: %{
            source_room_id: String.t(),
            direction: atom(),
            target_room_id: String.t(),
            visible_to_user_id: integer()
          }
        }

  @doc """
  Generate a transient-region spec for `owner_id`, entered from
  `source_room_id`. Layout: a `Rift Threshold` origin room, a `Whispering
  Hollow`, and a `Forgotten Alcove`, connected north/south and east/west,
  with a `:rift` return exit back to the source room.
  """
  @spec generate(integer(), String.t()) :: spec()
  def generate(owner_id, source_room_id)
      when is_integer(owner_id) and is_binary(source_room_id) do
    region_id = Ecto.UUID.generate()
    origin = Ecto.UUID.generate()
    hollow = Ecto.UUID.generate()
    alcove = Ecto.UUID.generate()

    %{
      region_id: region_id,
      name: "Transient Pocket #{String.slice(region_id, 0, 8)}",
      provision_owner_id: owner_id,
      source_room_id: source_room_id,
      origin_room_id: origin,
      rooms: [
        %{
          room_id: origin,
          name: "Rift Threshold",
          description:
            "A shimmering rift hangs in the air behind you. Cold mist coils around bare stone."
        },
        %{
          room_id: hollow,
          name: "Whispering Hollow",
          description: "A low hollow where faint voices seem to murmur just out of earshot."
        },
        %{
          room_id: alcove,
          name: "Forgotten Alcove",
          description:
            "A dead-end alcove, dust thick on every surface. Nothing has stirred here in ages."
        }
      ],
      intra_exits: [
        %{from: origin, direction: :north, to: hollow},
        %{from: hollow, direction: :south, to: origin},
        %{from: hollow, direction: :east, to: alcove},
        %{from: alcove, direction: :west, to: hollow},
        %{from: origin, direction: :rift, to: source_room_id}
      ],
      entry_exit: %{
        source_room_id: source_room_id,
        direction: :rift,
        target_room_id: origin,
        visible_to_user_id: owner_id
      }
    }
  end
end
