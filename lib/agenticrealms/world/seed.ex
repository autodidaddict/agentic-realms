defmodule AgenticRealms.World.Seed do
  @moduledoc """
  Idempotent starter-map seeder. Run from `priv/repo/seeds.exs`.

  Feature 012 (Maps) rewrite. The seeded world now lives inside two
  regions — Blackmire (primary, where players spawn) and Hollowvale (a
  stub region behind a cross-region exit). Every seed room carries
  explicit `(map_x, map_y, elevation)` so the map renderer has meaningful
  content on a fresh install.

  Layout (Blackmire, elevation 0 unless noted):

  ```text
              map_x   0      1      2      3       4
              ┌──────┬──────┬──────┬──────┬──────┐
  map_y = -1 │ Cor  │      │      │      │      │
              ├──────┼──────┼──────┼──────┼──────┤
  map_y =  0 │ Atr  │~~~~~~~~~~~~~~│ Lib  │ Vlt† │
              ├──────┼──────┼──────┼──────┼──────┤
  map_y =  1 │      │      │      │      │      │
              ├──────┼──────┼──────┼──────┼──────┤
  map_y =  2 │      │      │      │ Brd  │      │
              └──────┴──────┴──────┴──────┴──────┘
  ```

  `~~~` denotes the long-distance bridge (Atrium↔Library, Δx = 3).
  `Vlt†` is the Hidden Vault — `map_visible: false`, so it never appears
  on the map and the Library→Vault exit shows no affordance at all.

  Vertical: Atrium has an Up exit to the Atrium Loft at
  `(0, 0, elevation 1)`. Loft has a Down back to Atrium.

  Cross-region: Border (`3, 2, 0` in Blackmire) has an East exit into
  Hollowvale Outskirts (`0, 0, 0` in Hollowvale).

  The starting-room id is pinned in `@starting_room_id` so `SpawnPlayer`
  / `Seed.starting_room_id/0` continue to work unchanged.
  """

  require Logger

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Behaviors.Validator, as: BehaviorsValidator
  alias AgenticRealms.World.Commands, as: WorldCommands
  alias AgenticRealms.World.Schemas.{Region, Room}

  # --- regions
  @blackmire_region_id "00000000-0000-4000-8000-000000000010"
  @hollowvale_region_id "00000000-0000-4000-8000-000000000011"

  # --- rooms (UUIDs pinned for test stability)
  @starting_room_id "00000000-0000-4000-8000-000000000001"
  @corridor_room_id "00000000-0000-4000-8000-000000000002"
  @library_room_id "00000000-0000-4000-8000-000000000003"
  @loft_room_id "00000000-0000-4000-8000-000000000004"
  @vault_room_id "00000000-0000-4000-8000-000000000005"
  @border_room_id "00000000-0000-4000-8000-000000000006"
  @outskirts_room_id "00000000-0000-4000-8000-000000000007"

  # --- objects (existing)
  @brass_lantern_id "00000000-0000-4000-8000-100000000001"
  @leather_journal_id "00000000-0000-4000-8000-100000000002"
  @reading_lectern_id "00000000-0000-4000-8000-100000000003"

  # --- NPC (existing — feature 008 clone id preserved verbatim)
  @innkeeper_garrick_clone_id "00000000-0000-4000-8000-200000000001"
  @innkeeper_garrick_blueprint_id "garrick_the_innkeeper"

  @doc """
  Returns the UUID of the designated starting room. Stable across runs.
  """
  @spec starting_room_id() :: String.t()
  def starting_room_id, do: @starting_room_id

  @doc """
  Seed the world if not yet seeded. Idempotent: re-running is a no-op as
  long as either a region or a room already exists.
  """
  @spec run() :: :ok | :already_seeded
  def run do
    if Repo.aggregate(Room, :count) > 0 or Repo.aggregate(Region, :count) > 0 do
      Logger.info("[World.Seed] world already seeded — skipping")
      :already_seeded
    else
      Logger.info("[World.Seed] seeding starter map (Blackmire + Hollowvale)")
      do_seed()
      Logger.info("[World.Seed] starter map seeded")
      :ok
    end
  end

  defp do_seed do
    # ---- regions ----
    :ok = WorldCommands.create_region(@blackmire_region_id, "Blackmire")
    :ok = WorldCommands.create_region(@hollowvale_region_id, "Hollowvale")

    # ---- behaviors (carried over from feature 011) ----
    atrium_behaviors = [
      %{
        "trigger" => "player_entered",
        "actions" => [
          %{"type" => "say", "text" => "The cool air carries the scent of rain."}
        ]
      },
      %{
        "trigger" => "tick",
        "interval_ms" => 30_000,
        "actions" => [
          %{
            "type" => "emote",
            "text" => "Dust motes drift in the slanted afternoon light."
          }
        ]
      }
    ]

    :ok = validate_behaviors!(atrium_behaviors, "atrium_behaviors")

    garrick_behaviors = [
      %{
        "trigger" => "player_entered",
        "actions" => [
          %{"type" => "say", "text" => "Welcome to the Stone Atrium."}
        ]
      },
      %{
        "trigger" => "player_left",
        "actions" => [
          %{"type" => "say", "text" => "Farewell, traveler."}
        ]
      },
      %{
        "trigger" => "tick",
        "interval_ms" => 20_000,
        "actions" => [
          %{"type" => "emote", "text" => "polishes a tankard absentmindedly."}
        ]
      }
    ]

    :ok = validate_behaviors!(garrick_behaviors, "garrick_behaviors")

    garrick_lore =
      """
      You are Garrick, a former bridge-guard from the Riverford garrison. \
      You came south to the Stone Atrium twelve winters ago after the \
      Riverford collapse — a flood that swept your watchhouse into the \
      water and ended a dozen lives, including your captain's. You don't \
      speak of it directly unless the conversation earns it. You're \
      soft-spoken, patient, observant. You miss your old comrades but \
      have made an uneasy peace with innkeeping. You take pride in a \
      clean tankard and an honest welcome. You distrust nobles and like \
      travelers who pay for their second pint without being asked.\
      """
      |> String.replace("\n", " ")
      |> String.trim()

    lantern_behaviors = [
      %{
        "trigger" => "tick",
        "interval_ms" => 10_000,
        "actions" => [
          %{"type" => "emote", "text" => "flickers softly."}
        ]
      }
    ]

    :ok = validate_behaviors!(lantern_behaviors, "lantern_behaviors")

    # ---- Blackmire rooms ----
    :ok =
      WorldCommands.create_room(
        @starting_room_id,
        "Stone Atrium",
        "A wide, pillared hall of mossy granite. The air is cool and tastes faintly of rain. A single shaft of daylight falls from a slot high above, lighting motes of dust drifting in slow spirals.",
        @blackmire_region_id,
        behaviors: atrium_behaviors,
        elevation: 0,
        map_x: 0,
        map_y: 0
      )

    :ok =
      WorldCommands.create_room(
        @corridor_room_id,
        "North Corridor",
        "A narrow stone passage worn smooth by centuries of footsteps. The walls are bare. Your own breath sounds loud in the quiet.",
        @blackmire_region_id,
        elevation: 0,
        map_x: 0,
        map_y: -1
      )

    :ok =
      WorldCommands.create_room(
        @library_room_id,
        "Dusty Library",
        "Shelves of crumbling tomes line three walls, their spines cracked and silver-leafed. A heavy reading lectern stands beneath the only window, its surface scratched with the marks of generations of scribes.",
        @blackmire_region_id,
        elevation: 0,
        map_x: 3,
        map_y: 0
      )

    :ok =
      WorldCommands.create_room(
        @loft_room_id,
        "Atrium Loft",
        "A narrow gallery overlooking the atrium below. Wooden rails run the length of the floor; pigeons nest in the rafters.",
        @blackmire_region_id,
        elevation: 1,
        map_x: 0,
        map_y: 0
      )

    # The Vault is map-hidden — appears nowhere on the map even when discovered.
    :ok =
      WorldCommands.create_room(
        @vault_room_id,
        "Hidden Vault",
        "A windowless chamber lined with iron-shod chests. The air is dry and tastes of old copper. Whoever once kept this place left in a hurry.",
        @blackmire_region_id,
        map_visible: false,
        elevation: 0,
        map_x: 4,
        map_y: 0
      )

    :ok =
      WorldCommands.create_room(
        @border_room_id,
        "Blackmire Border",
        "A weathered stone marker the height of a tall man, scored with weather and lichen. Beyond it the road turns to packed earth and the country grows unfamiliar.",
        @blackmire_region_id,
        elevation: 0,
        map_x: 3,
        map_y: 2
      )

    # ---- Hollowvale stub ----
    :ok =
      WorldCommands.create_room(
        @outskirts_room_id,
        "Hollowvale Outskirts",
        "A village edge of crooked wooden fences and tilted gables. Smoke rises from a chimney far down the lane. The air smells of woodsmoke and turned earth.",
        @hollowvale_region_id,
        elevation: 0,
        map_x: 0,
        map_y: 0
      )

    # ---- Exits ----
    # Atrium ↔ Corridor (Δy = 1)
    :ok = WorldCommands.add_exit(@starting_room_id, :north, @corridor_room_id)
    :ok = WorldCommands.add_exit(@corridor_room_id, :south, @starting_room_id)

    # Atrium ↔ Library (Δx = 3 — long-distance "bridge" line)
    :ok = WorldCommands.add_exit(@starting_room_id, :east, @library_room_id)
    :ok = WorldCommands.add_exit(@library_room_id, :west, @starting_room_id)

    # Atrium ↔ Loft (up/down between elev 0 and 1)
    :ok = WorldCommands.add_exit(@starting_room_id, :up, @loft_room_id)
    :ok = WorldCommands.add_exit(@loft_room_id, :down, @starting_room_id)

    # Library ↔ Vault (east/west, distance 1). Vault is map-hidden so
    # neither line nor fog stub appears on Library's east side.
    :ok = WorldCommands.add_exit(@library_room_id, :east, @vault_room_id)
    :ok = WorldCommands.add_exit(@vault_room_id, :west, @library_room_id)

    # Library ↔ Border (south/north, Δy = 2)
    :ok = WorldCommands.add_exit(@library_room_id, :south, @border_room_id)
    :ok = WorldCommands.add_exit(@border_room_id, :north, @library_room_id)

    # Border → Hollowvale Outskirts (one-way east, cross-region). The
    # map renders a dashed cross-region affordance from Border's east side.
    :ok = WorldCommands.add_exit(@border_room_id, :east, @outskirts_room_id)
    # Return path west from Outskirts back to Border (two-way is friendlier;
    # the cross-region affordance still shows on both sides).
    :ok = WorldCommands.add_exit(@outskirts_room_id, :west, @border_room_id)

    # ---- Objects (existing) ----
    alias AgenticRealms.World.Commands.PlaceObject
    alias AgenticRealms.World.Application, as: WorldApp

    :ok =
      WorldApp.dispatch(%PlaceObject{
        room_id: @starting_room_id,
        object_id: @brass_lantern_id,
        name: "brass lantern",
        short_description: "a dented brass lantern",
        long_description:
          "An old hand-lantern of dented brass. Its glass is smoked but unbroken, and a stub of candle still rests within.",
        fixed: false,
        behaviors: lantern_behaviors
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

    # ---- NPC (existing) ----
    alias AgenticRealms.World.Commands.CreateNPCBlueprint

    :ok =
      WorldApp.dispatch(
        %CreateNPCBlueprint{
          blueprint_id: @innkeeper_garrick_blueprint_id,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper in a stained apron",
          long_description:
            "A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to.",
          behaviors: garrick_behaviors,
          lore: garrick_lore
        },
        consistency: :strong
      )

    {:ok, _} =
      WorldCommands.spawn_npc_clone(
        @innkeeper_garrick_blueprint_id,
        @starting_room_id,
        @innkeeper_garrick_clone_id
      )
  end

  defp validate_behaviors!(behaviors, label) do
    case BehaviorsValidator.validate(behaviors) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Seed authoring error in #{label}: #{inspect(reason)}"
    end
  end
end
