defmodule AgenticRealms.World.Behaviors.InterpreterTest do
  @moduledoc """
  Direct-invocation tests for the behavior interpreter (feature 009).
  Bypasses Commanded by calling `Interpreter.handle/2` with synthesized
  event structs and asserting broadcasts via PubSub subscriptions.

  See `specs/009-npc-behaviors/contracts/interpreter.md` test surface.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World
  alias AgenticRealms.World.Behaviors.Interpreter
  alias AgenticRealms.World.Events.PlayerMoved
  alias AgenticRealms.World.Schemas.{Room, PlayerState, NPCBlueprint, NPCClone}
  alias AgenticRealms.World.UIEvents.BehaviorUtterance
  alias AgenticRealmsWeb.Presence

  @pubsub AgenticRealms.PubSub

  # --- Fixtures -----------------------------------------------------------

  defp insert_room(behaviors \\ []) do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      behaviors: behaviors,
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp insert_blueprint do
    Repo.insert!(%NPCBlueprint{
      id: "test_bp_#{System.unique_integer([:positive])}",
      name: "Test NPC",
      short_description: "short",
      long_description: "long"
    })
  end

  defp insert_clone(blueprint, room, name, serial, behaviors) do
    Repo.insert!(%NPCClone{
      id: Ecto.UUID.generate(),
      blueprint_id: blueprint.id,
      serial: serial,
      name: name,
      short_description: "short",
      long_description: "long",
      room_id: room.id,
      behaviors: behaviors
    })
  end

  defp register_and_place(label, room) do
    suffix = System.unique_integer([:positive])

    {:ok, player} =
      Accounts.register_player(%{username: "#{label}_#{suffix}", password: "pw12345678"})

    Repo.insert!(%PlayerState{player_id: player.id, current_room_id: room.id})

    {:ok, _} = Presence.track_player(self(), player.id, player.username)
    Process.sleep(20)

    player
  end

  defp subscribe(player_id) do
    Phoenix.PubSub.subscribe(@pubsub, World.player_topic(player_id))
  end

  defp say_behavior(trigger, text) do
    %{"trigger" => trigger, "actions" => [%{"type" => "say", "text" => text}]}
  end

  # --- Tests --------------------------------------------------------------

  describe "fire_for_arrival/2 (player_entered firing on session arrival)" do
    test "empty room + no NPCs → no broadcasts" do
      room = insert_room()
      player = register_and_place("alice", room)
      subscribe(player.id)

      :ok = Interpreter.fire_for_arrival(player.id, room.id)

      refute_receive %BehaviorUtterance{}, 100
    end

    test "room-only player_entered behavior produces a :room_speech to triggering player" do
      room = insert_room([say_behavior("player_entered", "Hello scene.")])
      player = register_and_place("alice", room)
      subscribe(player.id)

      :ok = Interpreter.fire_for_arrival(player.id, room.id)

      assert_receive %BehaviorUtterance{
        kind: :room_speech,
        actor_name: nil,
        text: "Hello scene.",
        triggering_player_id: pid
      }

      assert pid == player.id
    end

    test ":room_speech is NOT delivered to non-triggering players" do
      room = insert_room([say_behavior("player_entered", "Hello.")])
      alice = register_and_place("alice", room)
      bob = register_and_place("bob", room)

      subscribe(bob.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      refute_receive %BehaviorUtterance{kind: :room_speech}, 100
    end

    test "NPC-only player_entered behavior produces :npc_speech to triggering player + others" do
      room = insert_room()
      blueprint = insert_blueprint()

      _clone =
        insert_clone(blueprint, room, "Garrick", 1, [say_behavior("player_entered", "Welcome.")])

      alice = register_and_place("alice", room)
      bob = register_and_place("bob", room)

      subscribe(alice.id)
      subscribe(bob.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      assert_receive %BehaviorUtterance{
        kind: :npc_speech,
        actor_name: "Garrick",
        text: "Welcome."
      }

      assert_receive %BehaviorUtterance{
        kind: :npc_speech,
        actor_name: "Garrick",
        text: "Welcome."
      }
    end

    test "room behavior fires BEFORE NPC behavior (FR-008a)" do
      room = insert_room([say_behavior("player_entered", "ROOM_FIRST")])
      blueprint = insert_blueprint()

      _clone =
        insert_clone(blueprint, room, "Garrick", 1, [say_behavior("player_entered", "NPC_SECOND")])

      alice = register_and_place("alice", room)
      subscribe(alice.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      assert_receive %BehaviorUtterance{kind: :room_speech, text: "ROOM_FIRST"}
      assert_receive %BehaviorUtterance{kind: :npc_speech, text: "NPC_SECOND"}
    end

    test "multi-behavior list fires in authored order" do
      room = insert_room()
      blueprint = insert_blueprint()

      _clone =
        insert_clone(blueprint, room, "Garrick", 1, [
          say_behavior("player_entered", "FIRST"),
          say_behavior("player_entered", "SECOND")
        ])

      alice = register_and_place("alice", room)
      subscribe(alice.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      assert_receive %BehaviorUtterance{kind: :npc_speech, text: "FIRST"}
      assert_receive %BehaviorUtterance{kind: :npc_speech, text: "SECOND"}
    end

    test "multi-action behavior fires actions in authored order" do
      room = insert_room()
      blueprint = insert_blueprint()

      multi_action_behavior = %{
        "trigger" => "player_entered",
        "actions" => [
          %{"type" => "say", "text" => "ALPHA"},
          %{"type" => "say", "text" => "BETA"}
        ]
      }

      _clone = insert_clone(blueprint, room, "Garrick", 1, [multi_action_behavior])
      alice = register_and_place("alice", room)
      subscribe(alice.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      assert_receive %BehaviorUtterance{text: "ALPHA"}
      assert_receive %BehaviorUtterance{text: "BETA"}
    end

    test "non-matching trigger → no firing" do
      room = insert_room()
      blueprint = insert_blueprint()

      # Only a player_left behavior; spawning should not fire it.
      _clone =
        insert_clone(blueprint, room, "Garrick", 1, [say_behavior("player_left", "Goodbye.")])

      alice = register_and_place("alice", room)
      subscribe(alice.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      refute_receive %BehaviorUtterance{}, 100
    end

    test "multiple NPC clones fire in serial order" do
      room = insert_room()
      blueprint = insert_blueprint()

      _ =
        insert_clone(blueprint, room, "First Guard", 1, [
          say_behavior("player_entered", "FROM_FIRST")
        ])

      _ =
        insert_clone(blueprint, room, "Second Guard", 2, [
          say_behavior("player_entered", "FROM_SECOND")
        ])

      alice = register_and_place("alice", room)
      subscribe(alice.id)

      :ok = Interpreter.fire_for_arrival(alice.id, room.id)

      assert_receive %BehaviorUtterance{text: "FROM_FIRST"}
      assert_receive %BehaviorUtterance{text: "FROM_SECOND"}
    end
  end

  describe "handle(%PlayerMoved{}) — fires player_entered in destination only" do
    test "fires player_entered behaviors in destination room (broadcast to triggering player)" do
      destination = insert_room([say_behavior("player_entered", "Destination greeting.")])

      # Source room must exist to keep the FK chain happy if the
      # interpreter were to consult it, even though we don't expect
      # player_left to fire from PlayerMoved.
      source = insert_room()

      alice = register_and_place("alice", source)
      subscribe(alice.id)

      :ok =
        Interpreter.handle(
          %PlayerMoved{
            player_id: alice.id,
            from_room_id: source.id,
            to_room_id: destination.id,
            direction: :north
          },
          %{}
        )

      assert_receive %BehaviorUtterance{kind: :room_speech, text: "Destination greeting."}
    end

    test "does NOT fire player_left from the PlayerMoved handler (it's inline-fired by GameLive)" do
      source = insert_room([say_behavior("player_left", "Source farewell.")])
      destination = insert_room()

      alice = register_and_place("alice", source)
      subscribe(alice.id)

      :ok =
        Interpreter.handle(
          %PlayerMoved{
            player_id: alice.id,
            from_room_id: source.id,
            to_room_id: destination.id,
            direction: :north
          },
          %{}
        )

      refute_receive %BehaviorUtterance{kind: :room_speech, text: "Source farewell."}, 100
    end
  end

  describe "fire_departure_inline/2" do
    test "returns log-entry maps for the triggering player (no broadcast back to them)" do
      source = insert_room([say_behavior("player_left", "Source farewell.")])
      blueprint = insert_blueprint()

      _clone =
        insert_clone(blueprint, source, "Garrick", 1, [
          say_behavior("player_left", "Farewell, traveler.")
        ])

      alice = register_and_place("alice", source)
      subscribe(alice.id)

      entries = Interpreter.fire_departure_inline(alice.id, source.id)

      # Room behavior first, then NPC behavior (FR-008a).
      assert [
               %{kind: :room_speech, text: "Source farewell."},
               %{kind: :npc_speech, actor_name: "Garrick", text: "Farewell, traveler."}
             ] = entries

      # Triggering player does NOT receive a broadcast back (the entries
      # are returned for inline-appending by the caller).
      refute_receive %BehaviorUtterance{text: "Source farewell."}, 100
      refute_receive %BehaviorUtterance{text: "Farewell, traveler."}, 100
    end

    test "broadcasts npc_speech to OTHER players in the source room" do
      source = insert_room()
      blueprint = insert_blueprint()

      _clone =
        insert_clone(blueprint, source, "Garrick", 1, [
          say_behavior("player_left", "Farewell, traveler.")
        ])

      alice = register_and_place("alice", source)
      bob = register_and_place("bob", source)

      subscribe(bob.id)

      _entries = Interpreter.fire_departure_inline(alice.id, source.id)

      # Bob (other player in source room) receives the farewell via PubSub.
      assert_receive %BehaviorUtterance{
        kind: :npc_speech,
        actor_name: "Garrick",
        text: "Farewell, traveler."
      }
    end

    test "does NOT broadcast room_speech to other players (anti-spam, FR-015)" do
      source = insert_room([say_behavior("player_left", "Source farewell.")])

      alice = register_and_place("alice", source)
      bob = register_and_place("bob", source)

      subscribe(bob.id)

      _entries = Interpreter.fire_departure_inline(alice.id, source.id)

      refute_receive %BehaviorUtterance{kind: :room_speech}, 100
    end
  end
end
