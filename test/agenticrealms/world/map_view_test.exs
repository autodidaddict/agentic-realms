defmodule AgenticRealms.World.MapViewTest do
  @moduledoc """
  Tests for `World.MapView.for_player/1`. Builds fixtures via direct
  `Repo.insert!` (bypassing the command pipeline) so each test isolates
  exactly the world shape it cares about, without needing the Commanded
  event store. Discovery rows are inserted directly here so the MapView
  layer sees a consistent read-model state.

  Feature 012 — Maps. Covers US1 (basic render), US2 (movement updates),
  and the off-map / cross-region / hidden-room negative cases that US5–US7
  will exercise further in subsequent phases.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.MapView

  alias AgenticRealms.World.Schemas.{
    Region,
    Room,
    Exit,
    PlayerState,
    PlayerDiscoveredRoom
  }

  # ----------------------------------------------------------------
  # Fixture helpers
  # ----------------------------------------------------------------

  defp insert_region(name_prefix \\ "TestRegion") do
    Repo.insert!(%Region{
      id: Ecto.UUID.generate(),
      name: "#{name_prefix}-#{System.unique_integer([:positive])}"
    })
  end

  defp insert_room(region, opts \\ []) do
    Repo.insert!(%Room{
      id: Keyword.get(opts, :id, Ecto.UUID.generate()),
      name: Keyword.get(opts, :name, "Test Room"),
      description: Keyword.get(opts, :description, "A room."),
      region_id: region.id,
      elevation: Keyword.get(opts, :elevation, 0),
      map_visible: Keyword.get(opts, :map_visible, true),
      map_x: Keyword.get(opts, :map_x),
      map_y: Keyword.get(opts, :map_y)
    })
  end

  defp insert_exit(source, direction, target) do
    Repo.insert!(%Exit{
      source_room_id: source.id,
      direction: to_string(direction),
      target_room_id: target.id
    })
  end

  defp insert_player_state(player_id, room_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %PlayerState{
        player_id: player_id,
        current_room_id: room_id,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [current_room_id: room_id, updated_at: now]],
      conflict_target: :player_id
    )
  end

  # Need a real player row for the FK to resolve. We use a deterministic
  # but unique id per test so async-shared sandboxes don't collide.
  defp insert_account_player do
    id = System.unique_integer([:positive])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%AgenticRealms.Accounts.Player{
      id: id,
      username: "test-player-#{id}",
      hashed_password: "$2b$04$00000000000000000000000000000000000000000000000000000",
      inserted_at: now,
      updated_at: now
    })

    id
  end

  defp discover(player_id, room) do
    Repo.insert!(%PlayerDiscoveredRoom{
      player_id: player_id,
      room_id: room.id,
      discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  # ----------------------------------------------------------------
  # US1 — basic render
  # ----------------------------------------------------------------

  describe "US1 — fresh player in a single discovered room" do
    setup do
      region = insert_region("Blackmire")
      atrium = insert_room(region, name: "Stone Atrium", map_x: 0, map_y: 0)
      player_id = insert_account_player()
      insert_player_state(player_id, atrium.id)
      discover(player_id, atrium)

      %{region: region, atrium: atrium, player_id: player_id}
    end

    test "renders exactly one room glyph, highlighted as current",
         %{region: region, atrium: atrium, player_id: player_id} do
      view = MapView.for_player(player_id)

      refute view.off_map?
      assert view.region_id == region.id
      assert view.region_name == region.name
      assert view.current_room_id == atrium.id
      assert length(view.rooms) == 1

      [glyph] = view.rooms
      assert glyph.id == atrium.id
      assert glyph.name == "Stone Atrium"
      assert glyph.is_current?
      assert glyph.x == 0
      assert glyph.y == 0
      refute glyph.has_up?
      refute glyph.has_down?
    end

    test "no exits when the room has none",
         %{player_id: player_id} do
      assert MapView.for_player(player_id).exits == []
    end

    test "no above/below affordances when only one elevation discovered",
         %{player_id: player_id} do
      view = MapView.for_player(player_id)
      refute view.has_above_rooms?
      refute view.has_below_rooms?
    end
  end

  describe "US1 — current room implicitly discovered (covers spawn race)" do
    setup do
      region = insert_region()
      atrium = insert_room(region, name: "Stone Atrium", map_x: 0, map_y: 0)
      player_id = insert_account_player()
      insert_player_state(player_id, atrium.id)
      # NOTE: NOT calling discover/2 — simulates the eventually-consistent
      # window between PlayerSpawned and PlayerDiscoveredRoom landing in the
      # read model.

      %{atrium: atrium, player_id: player_id}
    end

    test "the current room renders even without a discovery row yet",
         %{atrium: atrium, player_id: player_id} do
      view = MapView.for_player(player_id)
      assert [glyph] = view.rooms
      assert glyph.id == atrium.id
      assert glyph.is_current?
    end
  end

  describe "US1 — three linear discovered rooms produce two undirected lines" do
    setup do
      region = insert_region()
      a = insert_room(region, name: "A", map_x: 0, map_y: 0)
      b = insert_room(region, name: "B", map_x: 1, map_y: 0)
      c = insert_room(region, name: "C", map_x: 2, map_y: 0)

      # A <-> B (reciprocal)
      insert_exit(a, :east, b)
      insert_exit(b, :west, a)
      # B <-> C (reciprocal)
      insert_exit(b, :east, c)
      insert_exit(c, :west, b)

      player_id = insert_account_player()
      insert_player_state(player_id, b.id)
      for r <- [a, b, c], do: discover(player_id, r)

      %{a: a, b: b, c: c, player_id: player_id}
    end

    test "three rooms render, middle one is current",
         %{b: b, player_id: player_id} do
      view = MapView.for_player(player_id)

      assert length(view.rooms) == 3
      current = Enum.find(view.rooms, & &1.is_current?)
      assert current.id == b.id
      non_current = Enum.reject(view.rooms, & &1.is_current?)
      assert length(non_current) == 2
    end

    test "reciprocal exits dedupe to exactly two undirected lines (FR-004)",
         %{player_id: player_id} do
      view = MapView.for_player(player_id)
      assert length(view.exits) == 2
      assert Enum.all?(view.exits, &(&1.kind == :normal))
    end
  end

  # ----------------------------------------------------------------
  # US2 — map updates as the player moves
  # ----------------------------------------------------------------

  describe "US2 — movement-driven discovery shifts the rendered set" do
    setup do
      region = insert_region()
      atrium = insert_room(region, name: "Atrium", map_x: 0, map_y: 0)
      corridor = insert_room(region, name: "Corridor", map_x: 0, map_y: -1)
      insert_exit(atrium, :north, corridor)
      insert_exit(corridor, :south, atrium)

      player_id = insert_account_player()
      insert_player_state(player_id, atrium.id)
      discover(player_id, atrium)

      %{atrium: atrium, corridor: corridor, player_id: player_id}
    end

    test "before move: only the Atrium renders, but exit toward Corridor emits a fog stub",
         %{atrium: atrium, player_id: player_id} do
      view = MapView.for_player(player_id)
      assert [glyph] = view.rooms
      assert glyph.id == atrium.id

      assert [stub] = view.exits
      assert stub.kind == :fog_stub
      assert stub.from_x == atrium.map_x
      assert stub.from_y == atrium.map_y
      assert stub.direction == :north
      # Fog stub endpoint is fractional (~half a cell into the direction),
      # NOT the actual destination's coords.
      refute stub.to_y == -1
    end

    test "after the player moves into the Corridor: both rooms render, line connects them",
         %{atrium: atrium, corridor: corridor, player_id: player_id} do
      # Simulate the projector's emission flow: move + discovery
      insert_player_state(player_id, corridor.id)
      discover(player_id, corridor)

      view = MapView.for_player(player_id)

      assert length(view.rooms) == 2
      current = Enum.find(view.rooms, & &1.is_current?)
      assert current.id == corridor.id
      other = Enum.reject(view.rooms, & &1.is_current?) |> hd()
      assert other.id == atrium.id

      assert length(view.exits) == 1
      [line] = view.exits
      assert line.kind == :normal
    end

    test "moving back to an already-discovered room re-highlights it without dropping the other",
         %{atrium: atrium, corridor: corridor, player_id: player_id} do
      # Player visits Corridor (now discovered)
      insert_player_state(player_id, corridor.id)
      discover(player_id, corridor)

      # Then moves back to Atrium
      insert_player_state(player_id, atrium.id)

      view = MapView.for_player(player_id)
      assert length(view.rooms) == 2
      current = Enum.find(view.rooms, & &1.is_current?)
      assert current.id == atrium.id
    end
  end

  # ----------------------------------------------------------------
  # US3 — fog-of-war stubs + one-way exit info-hiding
  # ----------------------------------------------------------------

  describe "US3 — fog-of-war stubs" do
    test "undiscovered map-visible target produces a :fog_stub entry" do
      region = insert_region()
      a = insert_room(region, name: "A", map_x: 0, map_y: 0)
      b = insert_room(region, name: "B", map_x: 1, map_y: 0)
      insert_exit(a, :east, b)
      insert_exit(b, :west, a)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)
      # B is NOT discovered.

      view = MapView.for_player(player_id)

      assert length(view.exits) == 1
      [stub] = view.exits
      assert stub.kind == :fog_stub
      assert stub.from_x == 0
      assert stub.from_y == 0
      assert stub.direction == :east
    end

    test "fog stub endpoint is NOT the destination's actual coords (info hiding)" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      b = insert_room(region, map_x: 5, map_y: 0)
      insert_exit(a, :east, b)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)

      view = MapView.for_player(player_id)
      [stub] = view.exits
      # Stub points east but lands ~0.6 cells out — definitely not at x=5.
      assert stub.kind == :fog_stub
      assert stub.to_x < 1
      assert stub.to_x > 0
    end

    test "exit to a map-hidden target produces NO stub (FR-006 trumps fog)" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      hidden = insert_room(region, map_visible: false, map_x: 1, map_y: 0)
      insert_exit(a, :east, hidden)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)

      view = MapView.for_player(player_id)
      assert view.exits == []
    end

    test "exit to an off-map (coord-nil) target produces NO stub" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      off = insert_room(region, map_x: nil, map_y: nil)
      insert_exit(a, :east, off)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)

      view = MapView.for_player(player_id)
      assert view.exits == []
    end

    test "discovered + map-visible target collapses fog stub into a normal line" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      b = insert_room(region, map_x: 1, map_y: 0)
      insert_exit(a, :east, b)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)
      discover(player_id, b)

      view = MapView.for_player(player_id)
      [line] = view.exits
      assert line.kind == :normal
    end

    test "vertical exit (:up) to an undiscovered room does NOT produce a fog stub" do
      region = insert_region()
      ground = insert_room(region, name: "Ground", elevation: 0, map_x: 0, map_y: 0)
      _loft = insert_room(region, name: "Loft", elevation: 1, map_x: 0, map_y: 0)
      insert_exit(ground, :up, _loft)

      player_id = insert_account_player()
      insert_player_state(player_id, ground.id)
      discover(player_id, ground)

      view = MapView.for_player(player_id)
      # No line at all — :up turns into an icon (covered in US4).
      assert view.exits == []
    end
  end

  describe "US3 — one-way exit info-hiding" do
    test "a one-way A→B exit between discovered rooms still produces ONE undirected line" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      b = insert_room(region, map_x: 1, map_y: 0)
      # ONLY one direction (no B→A return)
      insert_exit(a, :east, b)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)
      discover(player_id, b)

      view = MapView.for_player(player_id)
      assert length(view.exits) == 1
      [line] = view.exits
      assert line.kind == :normal
      # The line is visually identical to a reciprocal pair's render — no
      # direction marker, no asymmetric styling at this layer.
    end
  end

  # ----------------------------------------------------------------
  # Off-map render (FR-003a) — also exercised by US5
  # ----------------------------------------------------------------

  describe "off-map render (FR-003a)" do
    test "player in a room with map_x = nil → blank map, region header only" do
      region = insert_region()
      off_map = insert_room(region, name: "Off Map", map_x: nil, map_y: nil)
      player_id = insert_account_player()
      insert_player_state(player_id, off_map.id)
      discover(player_id, off_map)

      view = MapView.for_player(player_id)

      assert view.off_map?
      assert view.region_id == region.id
      assert view.region_name == region.name
      assert view.rooms == []
      assert view.exits == []
      refute view.has_above_rooms?
      refute view.has_below_rooms?
    end

    test "player in a map_visible: false room → off-map render" do
      region = insert_region()
      hidden = insert_room(region, name: "Hidden", map_visible: false, map_x: 0, map_y: 0)
      player_id = insert_account_player()
      insert_player_state(player_id, hidden.id)
      discover(player_id, hidden)

      view = MapView.for_player(player_id)

      assert view.off_map?
      assert view.rooms == []
      assert view.exits == []
    end
  end

  # ----------------------------------------------------------------
  # Information-hiding sanity checks
  # ----------------------------------------------------------------

  describe "MapView.Exit struct shape — info-hiding contract" do
    test ":normal entries carry coords but no target room id" do
      region = insert_region()
      a = insert_room(region, map_x: 0, map_y: 0)
      b = insert_room(region, map_x: 1, map_y: 0)
      insert_exit(a, :east, b)
      insert_exit(b, :west, a)

      player_id = insert_account_player()
      insert_player_state(player_id, a.id)
      discover(player_id, a)
      discover(player_id, b)

      view = MapView.for_player(player_id)
      [line] = view.exits

      # The struct fields must be just these — no destination room id.
      refute Map.has_key?(line, :target_id)
      refute Map.has_key?(line, :to_room_id)
      refute Map.has_key?(line, :destination_id)
      assert line.kind == :normal
    end
  end
end
