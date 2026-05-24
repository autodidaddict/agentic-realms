defmodule AgenticRealms.World.ExamineTest do
  @moduledoc """
  Unit tests for `AgenticRealms.World.Examine` — the target resolution facade
  introduced in feature 006. Tests insert read-model rows directly via
  `Repo.insert!/1`, sidestepping Commanded — Examine is a pure read against
  the projected world state, so the event-source path is incidental.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Examine
  alias AgenticRealms.World.Examine.Match
  alias AgenticRealms.World.Schemas.{Object, PlayerState, Room, NPCBlueprint, NPCClone}
  alias AgenticRealmsWeb.Presence

  defp register_player(name) do
    suffix = System.unique_integer([:positive])

    {:ok, p} = Accounts.register_player(%{username: "#{name}_#{suffix}", password: "pw12345678"})

    p
  end

  defp insert_room(name \\ "Test Atrium") do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: name,
      description: "A room."
    })
  end

  defp insert_object(room_id, name, long_description, opts \\ []) do
    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: name,
      short_description: "a #{name}",
      long_description: long_description,
      fixed: Keyword.get(opts, :fixed, false),
      room_id: room_id,
      player_id: nil
    })
  end

  defp insert_inventory_object(player_id, name, long_description) do
    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: name,
      short_description: "a #{name}",
      long_description: long_description,
      fixed: false,
      room_id: nil,
      player_id: player_id
    })
  end

  defp place_in_room(player, room) do
    Repo.insert!(%PlayerState{
      player_id: player.id,
      current_room_id: room.id
    })
  end

  defp track_online(player) do
    {:ok, _} = Presence.track_player(self(), player.id, player.username)
    # Presence track is async — give it a moment to register before queries
    # that filter by online presence run.
    Process.sleep(20)
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # US1 — Room objects
  # ──────────────────────────────────────────────────────────────────────

  describe "examine/2 — room objects (US1)" do
    setup do
      alice = register_player("alice")
      room = insert_room()
      place_in_room(alice, room)
      track_online(alice)

      %{alice: alice, room: room}
    end

    test "exact case-insensitive match returns the object's long description",
         %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "An old hand-lantern of dented brass.")

      assert {:ok, %Match{target_kind: :object, name: "brass lantern", long_description: ld}} =
               Examine.examine(alice.id, "brass lantern")

      assert ld == "An old hand-lantern of dented brass."
    end

    test "uppercase target also matches", %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "A lantern.")

      assert {:ok, %Match{target_kind: :object, name: "brass lantern"}} =
               Examine.examine(alice.id, "brass lantern")
    end

    test "partial match resolves when unique", %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "A lantern.")

      assert {:ok, %Match{target_kind: :object, name: "brass lantern"}} =
               Examine.examine(alice.id, "lantern")
    end

    test "fixed objects are still examinable", %{alice: alice, room: room} do
      insert_object(room.id, "reading lectern", "Bolted to the floor.", fixed: true)

      assert {:ok, %Match{target_kind: :object, name: "reading lectern", long_description: ld}} =
               Examine.examine(alice.id, "reading lectern")

      assert ld == "Bolted to the floor."
    end

    test "no match returns :no_such_target", %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "x")

      assert {:error, :no_such_target} = Examine.examine(alice.id, "dragon")
    end

    test "ambiguous partial match returns :ambiguous_partial", %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "x")
      insert_object(room.id, "iron lantern", "y")

      assert {:error, :ambiguous_partial} = Examine.examine(alice.id, "lantern")
    end

    test "examining when player has no current room returns :no_current_room" do
      # Player exists but no PlayerState row was inserted.
      stranger = register_player("stranger")

      assert {:error, :no_current_room} = Examine.examine(stranger.id, "anything")
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # US2 — Inventory objects
  # ──────────────────────────────────────────────────────────────────────

  describe "examine/2 — inventory objects (US2)" do
    setup do
      alice = register_player("alice")
      room = insert_room()
      place_in_room(alice, room)
      track_online(alice)

      %{alice: alice, room: room}
    end

    test "inventory object resolves when not in the room", %{alice: alice} do
      insert_inventory_object(alice.id, "leather-bound journal", "A slim journal.")

      assert {:ok,
              %Match{target_kind: :object, name: "leather-bound journal", long_description: ld}} =
               Examine.examine(alice.id, "journal")

      assert ld == "A slim journal."
    end

    test "partial match against inventory only", %{alice: alice} do
      insert_inventory_object(alice.id, "brass lantern", "Carried lantern.")

      assert {:ok, %Match{target_kind: :object, name: "brass lantern", long_description: ld}} =
               Examine.examine(alice.id, "lantern")

      assert ld == "Carried lantern."
    end

    test "inventory wins over room on exact-match tiebreak",
         %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "Room lantern.")
      insert_inventory_object(alice.id, "brass lantern", "Carried lantern.")

      assert {:ok, %Match{target_kind: :object, name: "brass lantern", long_description: ld}} =
               Examine.examine(alice.id, "brass lantern")

      assert ld == "Carried lantern.",
             "inventory copy must win over room copy when both exact-match"
    end

    test "multiple identically named objects in inventory → :ambiguous_in_inventory",
         %{alice: alice} do
      insert_inventory_object(alice.id, "brass lantern", "A")
      insert_inventory_object(alice.id, "brass lantern", "B")

      assert {:error, :ambiguous_in_inventory} = Examine.examine(alice.id, "brass lantern")
    end

    test "multiple identically named objects in room (none in inventory) → :ambiguous_in_room",
         %{alice: alice, room: room} do
      insert_object(room.id, "brass lantern", "A")
      insert_object(room.id, "brass lantern", "B")

      assert {:error, :ambiguous_in_room} = Examine.examine(alice.id, "brass lantern")
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # US3 — Players and self
  # ──────────────────────────────────────────────────────────────────────

  describe "examine/2 — players and self (US3)" do
    setup do
      alice = register_player("alice")
      bob = register_player("bob")
      room = insert_room()
      place_in_room(alice, room)
      place_in_room(bob, room)
      track_online(alice)
      track_online(bob)

      %{alice: alice, bob: bob, room: room}
    end

    test "examining a same-room player returns a :player Match with their stored username",
         %{alice: alice, bob: bob} do
      assert {:ok, %Match{target_kind: :player, name: name, long_description: nil}} =
               Examine.examine(bob.id, String.downcase(alice.username))

      assert name == alice.username
    end

    test "uppercase target matches case-insensitively", %{alice: alice, bob: bob} do
      assert {:ok, %Match{target_kind: :player, name: name}} =
               Examine.examine(bob.id, String.upcase(alice.username))

      assert name == alice.username
    end

    test "__self__ sentinel resolves to the acting player without scope lookup",
         %{alice: alice} do
      assert {:ok, %Match{target_kind: :player, name: name, long_description: nil}} =
               Examine.examine(alice.id, "__self__")

      assert name == alice.username
    end

    test "examining self by exact name also works", %{alice: alice} do
      assert {:ok, %Match{target_kind: :player, name: name}} =
               Examine.examine(alice.id, String.downcase(alice.username))

      assert name == alice.username
    end

    test "offline players are not examinable", %{alice: alice, bob: bob, room: _room} do
      # Re-register Alice but DO NOT track her in presence
      offline = register_player("ghost")
      Repo.insert!(%PlayerState{player_id: offline.id, current_room_id: bob_room_id(bob)})

      assert {:error, :no_such_target} =
               Examine.examine(alice.id, String.downcase(offline.username))
    end

    test "object + player exact-name collision returns :ambiguous_mixed_kind",
         %{alice: alice, room: room} do
      # Register a player whose username happens to match an object's name
      twin = register_player("Lantern")
      place_in_room(twin, room)
      track_online(twin)

      # Object of the same name (lowercased) in the room
      insert_object(room.id, String.downcase(twin.username), "An object.")

      assert {:error, :ambiguous_mixed_kind} =
               Examine.examine(alice.id, String.downcase(twin.username))
    end
  end

  # Helper for the offline test — fetches the bob_room_id from his PlayerState
  defp bob_room_id(bob) do
    Repo.get!(PlayerState, bob.id).current_room_id
  end

  # ──────────────────────────────────────────────────────────────────────
  # Feature 007 — Static NPCs
  # ──────────────────────────────────────────────────────────────────────

  defp insert_npc(room_id, name, long_description) do
    blueprint_id = "test_blueprint_#{System.unique_integer([:positive])}"

    Repo.insert!(%NPCBlueprint{
      id: blueprint_id,
      name: name,
      short_description: "a #{name}",
      long_description: long_description,
      is_synthetic: false
    })

    Repo.insert!(%NPCClone{
      id: Ecto.UUID.generate(),
      blueprint_id: blueprint_id,
      serial: 1,
      name: name,
      short_description: "a #{name}",
      long_description: long_description,
      room_id: room_id
    })
  end

  describe "examine/2 — NPCs (feature 007)" do
    setup do
      alice = register_player("alice")
      room = insert_room()
      place_in_room(alice, room)
      track_online(alice)

      garrick =
        insert_npc(
          room.id,
          "Garrick the Innkeeper",
          "A wiry man in a stained apron, his hands callused and his eyes patient."
        )

      %{alice: alice, room: room, garrick: garrick}
    end

    test "exact-name match returns an NPC Match", %{alice: alice} do
      assert {:ok,
              %Match{
                target_kind: :npc,
                name: "Garrick the Innkeeper",
                long_description: ld
              }} = Examine.examine(alice.id, "garrick the innkeeper")

      assert ld =~ "wiry man in a stained apron"
    end

    test "partial substring match returns the NPC", %{alice: alice} do
      assert {:ok, %Match{target_kind: :npc, name: "Garrick the Innkeeper"}} =
               Examine.examine(alice.id, "garrick")
    end

    test "NPC name is case-insensitive", %{alice: alice} do
      assert {:ok, %Match{target_kind: :npc, name: "Garrick the Innkeeper"}} =
               Examine.examine(alice.id, "GARRICK")
    end

    test "NPC in another room is not findable", %{alice: alice} do
      other_room = insert_room("Other Room")
      insert_npc(other_room.id, "Maelyn", "A bard.")

      assert {:error, :no_such_target} = Examine.examine(alice.id, "maelyn")
    end

    test "NPC + same-named room object → :ambiguous_mixed_kind", %{alice: alice, room: room} do
      insert_object(room.id, "garrick the innkeeper", "An object that happens to share the name.")

      assert {:error, :ambiguous_mixed_kind} =
               Examine.examine(alice.id, "garrick the innkeeper")
    end

    test "NPC + same-named player in the same room → :ambiguous_mixed_kind",
         %{room: room} do
      # Player usernames are constrained to letters/numbers/hyphens/underscores,
      # AND register_player suffixes the username for uniqueness. Set up the
      # collision by inserting an NPC whose name equals the twin's actual
      # registered username.
      alice = register_player("alice_obs")
      place_in_room(alice, room)
      track_online(alice)

      twin = register_player("warden")
      place_in_room(twin, room)
      track_online(twin)

      insert_npc(room.id, twin.username, "A grim warden in dented mail.")

      assert {:error, :ambiguous_mixed_kind} = Examine.examine(alice.id, twin.username)
    end

    test "self-aliases never resolve to an NPC", %{alice: alice, room: room} do
      insert_npc(room.id, "me", "An NPC literally named 'me'.")

      # `me` short-circuits to the acting player, NOT the NPC.
      assert {:ok, %Match{target_kind: :player, name: name}} =
               Examine.examine(alice.id, "me")

      refute name == "me"
      assert name == Accounts.get_player(alice.id).username
    end

    test "exact-matching inventory object wins over partially-matching NPC", %{alice: alice} do
      # The NPC's full name "Garrick the Innkeeper" only PARTIALLY matches
      # the input "garrick". The inventory object's name exact-matches.
      # Stage-1 exact resolution returns the inventory object — no NPC tie.
      insert_inventory_object(alice.id, "garrick", "An inventory item named garrick.")

      assert {:ok, %Match{target_kind: :object, name: "garrick", long_description: ld}} =
               Examine.examine(alice.id, "garrick")

      assert ld =~ "inventory item"
    end

    test "telemetry emits clone_debug_id on successful NPC match (FR-011)",
         %{alice: alice, garrick: garrick} do
      handler_id = "examine-debug-id-watcher-#{System.unique_integer([:positive])}"
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:agenticrealms, :examine, :resolve],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, metadata})
        end,
        nil
      )

      try do
        assert {:ok, %Match{target_kind: :npc}} =
                 Examine.examine(alice.id, "garrick the innkeeper")

        assert_receive {^ref, metadata}, 200

        expected_debug = "#{garrick.name}##{garrick.serial}"
        assert metadata.clone_debug_id == expected_debug
        assert metadata.target_kind == :npc
      after
        :telemetry.detach(handler_id)
      end
    end
  end
end
