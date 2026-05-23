defmodule AgenticRealms.World.Seed do
  @moduledoc """
  Idempotent starter-map seeder. Run from `priv/repo/seeds.exs`.

  Dispatches the sequence of `CreateRoom` / `AddExit` / `PlaceObject`
  commands described in `specs/003-persisted-world/research.md` §D8:

    * room_atrium (starting) — Stone Atrium with a brass lantern
    * room_corridor — North Corridor (empty)
    * room_library — Dusty Library with a leather-bound journal
      and a fixed reading lectern

  Paired exits atrium↔corridor (north/south) and atrium↔library (east/west).

  The starting-room id is fixed in `@starting_room_id` so subsequent code
  (`SpawnPlayer`, FR-022 recovery) can reference it without a DB lookup.
  """

  require Logger

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands.{CreateRoom, AddExit, PlaceObject, SpawnNPC}
  alias AgenticRealms.World.Schemas.Room

  @starting_room_id "00000000-0000-4000-8000-000000000001"
  @corridor_room_id "00000000-0000-4000-8000-000000000002"
  @library_room_id "00000000-0000-4000-8000-000000000003"

  @brass_lantern_id "00000000-0000-4000-8000-100000000001"
  @leather_journal_id "00000000-0000-4000-8000-100000000002"
  @reading_lectern_id "00000000-0000-4000-8000-100000000003"

  @innkeeper_garrick_id "00000000-0000-4000-8000-200000000001"

  @doc """
  Returns the UUID of the designated starting room. Stable across runs
  because the seed pins every entity id.
  """
  @spec starting_room_id() :: String.t()
  def starting_room_id, do: @starting_room_id

  @doc """
  Seed the world if not yet seeded. Idempotent: re-running is a no-op.
  """
  @spec run() :: :ok | :already_seeded
  def run do
    if Repo.aggregate(Room, :count) > 0 do
      Logger.info("[World.Seed] world already seeded — skipping")
      :already_seeded
    else
      Logger.info("[World.Seed] seeding starter map")
      do_seed()
      Logger.info("[World.Seed] starter map seeded")
      :ok
    end
  end

  defp do_seed do
    # Rooms
    :ok =
      WorldApp.dispatch(%CreateRoom{
        room_id: @starting_room_id,
        name: "Stone Atrium",
        description:
          "A wide, pillared hall of mossy granite. The air is cool and tastes faintly of rain. A single shaft of daylight falls from a slot high above, lighting motes of dust drifting in slow spirals."
      })

    :ok =
      WorldApp.dispatch(%CreateRoom{
        room_id: @corridor_room_id,
        name: "North Corridor",
        description:
          "A narrow stone passage worn smooth by centuries of footsteps. The walls are bare. Your own breath sounds loud in the quiet."
      })

    :ok =
      WorldApp.dispatch(%CreateRoom{
        room_id: @library_room_id,
        name: "Dusty Library",
        description:
          "Shelves of crumbling tomes line three walls, their spines cracked and silver-leafed. A heavy reading lectern stands beneath the only window, its surface scratched with the marks of generations of scribes."
      })

    # Exits (paired both directions)
    :ok =
      WorldApp.dispatch(%AddExit{
        room_id: @starting_room_id,
        direction: :north,
        target_room_id: @corridor_room_id
      })

    :ok =
      WorldApp.dispatch(%AddExit{
        room_id: @corridor_room_id,
        direction: :south,
        target_room_id: @starting_room_id
      })

    :ok =
      WorldApp.dispatch(%AddExit{
        room_id: @starting_room_id,
        direction: :east,
        target_room_id: @library_room_id
      })

    :ok =
      WorldApp.dispatch(%AddExit{
        room_id: @library_room_id,
        direction: :west,
        target_room_id: @starting_room_id
      })

    # Objects
    :ok =
      WorldApp.dispatch(%PlaceObject{
        room_id: @starting_room_id,
        object_id: @brass_lantern_id,
        name: "brass lantern",
        short_description: "a dented brass lantern",
        long_description:
          "An old hand-lantern of dented brass. Its glass is smoked but unbroken, and a stub of candle still rests within.",
        fixed: false
      })

    :ok =
      WorldApp.dispatch(%PlaceObject{
        room_id: @library_room_id,
        object_id: @leather_journal_id,
        name: "leather-bound journal",
        short_description: "a slim leather-bound journal",
        long_description:
          "A slim journal bound in oxblood leather, its pages thick and uneven. Most are blank; a few near the front are densely written in a hand you do not recognize.",
        fixed: false
      })

    :ok =
      WorldApp.dispatch(%PlaceObject{
        room_id: @library_room_id,
        object_id: @reading_lectern_id,
        name: "reading lectern",
        short_description: "a heavy reading lectern",
        long_description:
          "A heavy oak lectern, scratched and ink-stained from generations of use. It is bolted to the floor — there is no moving it.",
        fixed: true
      })

    # NPCs (feature 007)
    :ok =
      WorldApp.dispatch(%SpawnNPC{
        room_id: @starting_room_id,
        npc_id: @innkeeper_garrick_id,
        name: "Garrick the Innkeeper",
        short_description: "a wiry innkeeper in a stained apron",
        long_description:
          "A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to."
      })
  end
end
