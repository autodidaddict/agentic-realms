defmodule AgenticRealms.World.NPCChatTest do
  @moduledoc """
  Tests for the public NPCChat API. Exercises input
  validation, NPC resolution, and the Horde-backed find-or-start path.

  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealmsWeb.Topics
  alias AgenticRealms.World.NPCChat
  alias AgenticRealms.World.Schemas.{Blueprint, NPCClone, PlayerState, Room}
  alias AgenticRealms.World.UIEvents.{ChatSystemMessage, ChatUtterance}

  @pubsub AgenticRealms.PubSub

  defp insert_room do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp insert_blueprint(opts \\ []) do
    Repo.insert!(%Blueprint{
      id: "test_bp_#{System.unique_integer([:positive])}",
      name: Keyword.get(opts, :name, "Test Blueprint"),
      short_description: "short",
      long_description: "long",
      lore: Keyword.get(opts, :lore, "")
    })
  end

  defp insert_clone(blueprint, room, opts \\ []) do
    Repo.insert!(%NPCClone{
      id: Ecto.UUID.generate(),
      blueprint_id: blueprint.id,
      name: Keyword.get(opts, :name, "Garrick"),
      short_description: "short",
      long_description: "long",
      room_id: room.id,
      lore: Keyword.get(opts, :lore, blueprint.lore)
    })
  end

  defp register_and_place(label, room) do
    suffix = System.unique_integer([:positive])

    {:ok, player} =
      Accounts.register_player(%{username: "#{label}_#{suffix}", password: "pw12345678"})

    Repo.insert!(%PlayerState{player_id: player.id, current_room_id: room.id})
    player
  end

  defp setup_world(_) do
    Req.Test.set_req_test_to_shared(%{})
    room = insert_room()
    blueprint = insert_blueprint(lore: "Some lore.")
    clone = insert_clone(blueprint, room)
    player = register_and_place("alice", room)
    Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(player.id))
    %{room: room, blueprint: blueprint, clone: clone, player: player}
  end

  defp stub_say(text) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "tool_use", "name" => "say", "input" => %{"text" => text}}]
      })
    end)
  end

  describe "input validation" do
    setup [:setup_world]

    test "empty message → :empty_message", %{player: p} do
      assert {:error, :empty_message} = NPCChat.send(p.id, "Garrick", "")
      assert {:error, :empty_message} = NPCChat.send(p.id, "Garrick", "   ")
    end

    test "too-long message → :too_long", %{player: p} do
      long = String.duplicate("x", 501)
      assert {:error, :too_long} = NPCChat.send(p.id, "Garrick", long)
    end
  end

  describe "NPC resolution" do
    setup [:setup_world]

    test ":no_such_npc when the room has no matching NPC", %{player: p} do
      assert {:error, {:no_such_npc, "nobody"}} =
               NPCChat.send(p.id, "nobody", "hi")
    end

    test "case-insensitive exact match resolves successfully", %{
      player: p,
      clone: clone
    } do
      stub_say("Hi.")
      assert {:ok, :new} = NPCChat.send(p.id, "garrick", "hi")
      assert {:ok, _pid} = NPCChat.find(p.id, clone.id)
    end

    test "partial substring match resolves uniquely", %{player: p, clone: clone} do
      stub_say("Hi.")
      assert {:ok, :new} = NPCChat.send(p.id, "gar", "hi")
      assert {:ok, _pid} = NPCChat.find(p.id, clone.id)
    end

    test "ambiguous partial match → :ambiguous_npc", %{room: room} do
      bp = insert_blueprint(name: "Guards", lore: "")
      _g1 = insert_clone(bp, room, name: "Town Guard")
      _g2 = insert_clone(bp, room, name: "Guard Captain")

      {:ok, player} =
        Accounts.register_player(%{
          username: "bob_#{System.unique_integer([:positive])}",
          password: "pw12345678"
        })

      Repo.insert!(%PlayerState{player_id: player.id, current_room_id: room.id})

      assert {:error, {:ambiguous_npc, candidates}} =
               NPCChat.send(player.id, "guard", "hi")

      assert "Town Guard" in candidates
      assert "Guard Captain" in candidates
    end
  end

  describe "find/2" do
    setup [:setup_world]

    test "returns :error for an unstarted conversation", %{player: p, clone: clone} do
      assert :error = NPCChat.find(p.id, clone.id)
    end

    test "returns {:ok, pid} after a successful send", %{player: p, clone: clone} do
      stub_say("Hi.")
      {:ok, :new} = NPCChat.send(p.id, "Garrick", "hi")

      assert_receive %ChatUtterance{kind: :chat_speech}, 2_000

      assert {:ok, pid} = NPCChat.find(p.id, clone.id)
      assert Process.alive?(pid)
    end
  end

  describe "send/3 happy path" do
    setup [:setup_world]

    test "first send returns {:ok, :new} and the reply broadcasts as :chat_speech",
         %{player: p} do
      stub_say("Welcome.")

      assert {:ok, :new} = NPCChat.send(p.id, "Garrick", "hi")
      assert_receive %ChatSystemMessage{kind: :chat_new}
      assert_receive %ChatUtterance{kind: :chat_speech, text: "Welcome."}, 2_000
    end
  end
end
