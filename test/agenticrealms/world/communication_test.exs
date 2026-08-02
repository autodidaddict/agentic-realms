defmodule AgenticRealms.World.CommunicationTest do
  @moduledoc """
  Unit tests for the `AgenticRealms.World.Communication` facade.

  These tests subscribe to PubSub topics directly and assert on broadcast
  payloads, bypassing both the parser and `GameLive`. They cover validation
  rules and the broadcast contract per
  `specs/004-player-communication/contracts/communication_api.md`.

  See the LiveView integration tests for end-to-end multi-session behavior.

  Tell tests need DB access (RecipientResolver queries Accounts.Player) and
  Presence tracking, so the module uses `DataCase` with `async: false`.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealmsWeb.Topics
  alias AgenticRealms.World.Communication
  alias AgenticRealms.World.UIEvents.{RoomUtterance, PrivateUtterance}
  alias AgenticRealmsWeb.Presence

  @pubsub AgenticRealms.PubSub

  defp sender(overrides \\ %{}) do
    Map.merge(
      %{
        id: 42,
        name: "Alice",
        session_id: make_ref(),
        room_id: "room-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      },
      overrides
    )
  end

  describe "say/2" do
    test "rejects empty text" do
      assert {:error, :empty} = Communication.say(sender(), "")
      assert {:error, :empty} = Communication.say(sender(), "   ")
      assert {:error, :empty} = Communication.say(sender(), "\n\t  ")
    end

    test "rejects text over 500 characters (after trim)" do
      too_long = String.duplicate("x", 501)
      assert {:error, :too_long} = Communication.say(sender(), too_long)
    end

    test "accepts exactly 500 characters" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))
      text = String.duplicate("x", 500)
      assert :ok = Communication.say(sender, text)
      assert_receive %RoomUtterance{kind: :say, text: ^text}
    end

    test "broadcasts on the sender's room topic with kind: :say and the sender context" do
      sender = sender()
      sender_room_id = sender.room_id
      session_id = sender.session_id
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender_room_id))

      assert :ok = Communication.say(sender, "hello there")

      assert_receive %RoomUtterance{
        room_id: ^sender_room_id,
        actor_id: 42,
        actor_name: "Alice",
        actor_session_id: ^session_id,
        kind: :say,
        text: "hello there",
        recipient_id: nil
      }
    end

    test "trims surrounding whitespace before broadcasting" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.say(sender, "  hi  ")
      assert_receive %RoomUtterance{kind: :say, text: "hi"}
    end

    test "preserves internal whitespace in broadcast text" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.say(sender, "hi   mom")
      assert_receive %RoomUtterance{kind: :say, text: "hi   mom"}
    end

    test "preserves casing of broadcast text" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.say(sender, "HELLO World")
      assert_receive %RoomUtterance{kind: :say, text: "HELLO World"}
    end

    test "does NOT broadcast on a different room's topic" do
      sender = sender()
      other_room_id = "room-ffffffff-ffff-ffff-ffff-ffffffffffff"
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(other_room_id))

      assert :ok = Communication.say(sender, "hello")
      refute_receive _, 50
    end
  end

  describe "emote/2" do
    test "rejects empty text" do
      assert {:error, :empty} = Communication.emote(sender(), "")
      assert {:error, :empty} = Communication.emote(sender(), "   ")
    end

    test "rejects text over 500 characters" do
      assert {:error, :too_long} = Communication.emote(sender(), String.duplicate("x", 501))
    end

    test "broadcasts as :emote on sender's room topic" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.emote(sender, "waves at the fire")
      assert_receive %RoomUtterance{kind: :emote, text: "waves at the fire."}
    end

    test "appends a trailing period when text does not end in . ! or ?" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.emote(sender, "waves")
      assert_receive %RoomUtterance{kind: :emote, text: "waves."}
    end

    test "preserves trailing period" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.emote(sender, "stands silent.")
      assert_receive %RoomUtterance{kind: :emote, text: "stands silent."}
    end

    test "preserves trailing exclamation mark (no double-punctuation)" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.emote(sender, "laughs!")
      assert_receive %RoomUtterance{kind: :emote, text: "laughs!"}
    end

    test "preserves trailing question mark" do
      sender = sender()
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(sender.room_id))

      assert :ok = Communication.emote(sender, "tilts head?")
      assert_receive %RoomUtterance{kind: :emote, text: "tilts head?"}
    end
  end

  describe "tell/3" do
    setup do
      suffix = System.unique_integer([:positive])

      {:ok, alice} =
        Accounts.register_player(%{username: "alice_#{suffix}", password: "pw12345678"})

      {:ok, bob} = Accounts.register_player(%{username: "bob_#{suffix}", password: "pw12345678"})

      # Feature 021 — players are addressed by their character's name.
      alice_name = AgenticRealms.DataCase.create_character!(alice.id, name: "Alice#{suffix}")
      bob_name = AgenticRealms.DataCase.create_character!(bob.id, name: "Bob#{suffix}")

      alice_sender = %{
        id: alice.id,
        name: alice_name,
        session_id: make_ref(),
        room_id: "room-aaaa"
      }

      %{
        alice: alice,
        bob: bob,
        alice_name: alice_name,
        bob_name: bob_name,
        alice_sender: alice_sender,
        suffix: suffix
      }
    end

    test "rejects empty text", %{alice_sender: sender, bob_name: bob_name} do
      assert {:error, :empty} = Communication.tell(sender, bob_name, "")
      assert {:error, :empty} = Communication.tell(sender, bob_name, "   ")
    end

    test "rejects text over 500 characters", %{alice_sender: sender, bob_name: bob_name} do
      assert {:error, :too_long} =
               Communication.tell(sender, bob_name, String.duplicate("x", 501))
    end

    test "refuses when recipient is not found", %{alice_sender: sender} do
      assert {:error, :not_found} = Communication.tell(sender, "nobody_zz", "hi")
    end

    test "refuses self-target", %{alice_sender: sender, alice_name: alice_name} do
      assert {:error, :self_target} = Communication.tell(sender, alice_name, "hi")
    end

    test "refuses with :not_deliverable when recipient has no presence-tracked sessions",
         %{alice_sender: sender, bob_name: bob_name} do
      # No Presence.track has happened for bob → he is "offline".
      assert {:error, :not_deliverable} = Communication.tell(sender, bob_name, "hi")
    end

    test "broadcasts on player:<recipient_id> when recipient is online",
         %{alice_sender: sender, bob: bob, bob_name: bob_name} do
      # Track bob's presence from this test process so the online check passes.
      {:ok, _} = Presence.track_player(self(), bob.id, bob_name)
      # Subscribe to bob's topic to capture the broadcast.
      Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(bob.id))

      assert {:ok, %{recipient_id: rid, recipient_name: rname}} =
               Communication.tell(sender, bob_name, "psst")

      assert rid == bob.id
      assert rname == bob_name
      assert_receive %PrivateUtterance{kind: :tell, text: "psst", actor_id: actor_id}
      assert actor_id == sender.id
    end

    test "case-insensitive recipient resolution", %{
      alice_sender: sender,
      bob: bob,
      bob_name: bob_name,
      suffix: suffix
    } do
      {:ok, _} = Presence.track_player(self(), bob.id, bob_name)
      Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(bob.id))

      # bob's character is "Bob<suffix>" — try it shouted.
      assert {:ok, %{recipient_id: rid}} =
               Communication.tell(sender, "BOB#{suffix}", "yo")

      assert rid == bob.id
      assert_receive %PrivateUtterance{kind: :tell, text: "yo"}
    end
  end

  describe "whisper/3 — error paths (room-scope success path covered in integration tests)" do
    setup do
      suffix = System.unique_integer([:positive])

      {:ok, alice} =
        Accounts.register_player(%{username: "alice_#{suffix}", password: "pw12345678"})

      {:ok, bob} = Accounts.register_player(%{username: "bob_#{suffix}", password: "pw12345678"})

      alice_name = AgenticRealms.DataCase.create_character!(alice.id, name: "Alice#{suffix}")
      bob_name = AgenticRealms.DataCase.create_character!(bob.id, name: "Bob#{suffix}")

      alice_sender = %{
        id: alice.id,
        name: alice_name,
        session_id: make_ref(),
        # Valid UUID v4 — world_rooms.id is :binary_id.
        room_id: Ecto.UUID.generate()
      }

      %{
        alice: alice,
        bob: bob,
        alice_name: alice_name,
        bob_name: bob_name,
        alice_sender: alice_sender
      }
    end

    test "rejects empty text", %{alice_sender: sender, bob_name: bob_name} do
      assert {:error, :empty} = Communication.whisper(sender, bob_name, "")
      assert {:error, :empty} = Communication.whisper(sender, bob_name, "   ")
    end

    test "rejects text over 500 characters", %{alice_sender: sender, bob_name: bob_name} do
      assert {:error, :too_long} =
               Communication.whisper(sender, bob_name, String.duplicate("x", 501))
    end

    test "refuses when recipient is not found", %{alice_sender: sender} do
      assert {:error, :not_found} = Communication.whisper(sender, "nobody_zz", "hi")
    end

    test "refuses self-target", %{alice_sender: sender, alice_name: alice_name} do
      assert {:error, :self_target} = Communication.whisper(sender, alice_name, "hi")
    end

    test "refuses :recipient_not_in_room when neither party occupies the room",
         %{alice_sender: sender, bob_name: bob_name} do
      # The sender's `room_id` is a freshly-generated UUID with no player_state
      # rows pointing to it, so `other_occupants_of` returns [] and the
      # recipient is correctly not found in scope.
      assert {:error, :recipient_not_in_room} = Communication.whisper(sender, bob_name, "hi")
    end
  end
end
