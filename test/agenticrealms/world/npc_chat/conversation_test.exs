defmodule AgenticRealms.World.NPCChat.ConversationTest do
  @moduledoc """
  Tests for the Conversation GenServer (feature 010).

  Bypasses the Horde registry by `start_supervised`-ing a Conversation
  with `name: nil` so the same module can be exercised directly without
  cluster registration getting in the way.

  Stubs the Anthropic call via `Req.Test` so the test stays hermetic.

  See `specs/010-npc-conversations/contracts/conversation.md`.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World
  alias AgenticRealms.World.NPCChat.Conversation
  alias AgenticRealms.World.Schemas.{NPCBlueprint, NPCClone, PlayerState, Room}
  alias AgenticRealms.World.UIEvents.{ChatSystemMessage, ChatUtterance}

  @pubsub AgenticRealms.PubSub

  # --- Fixtures -----------------------------------------------------------

  defp insert_room do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp insert_blueprint do
    Repo.insert!(%NPCBlueprint{
      id: "test_bp_#{System.unique_integer([:positive])}",
      name: "Test Blueprint",
      short_description: "short",
      long_description: "long",
      lore: "A test NPC's lore."
    })
  end

  defp insert_clone(blueprint, room, opts \\ []) do
    Repo.insert!(%NPCClone{
      id: Ecto.UUID.generate(),
      blueprint_id: blueprint.id,
      serial: 1,
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

  defp subscribe(player_id) do
    Phoenix.PubSub.subscribe(@pubsub, World.player_topic(player_id))
  end

  defp stub_say(text) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "name" => "say", "input" => %{"text" => text}}
        ]
      })
    end)
  end

  defp stub_emote(text) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "name" => "emote", "input" => %{"text" => text}}
        ]
      })
    end)
  end

  defp stub_500 do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Plug.Conn.send_resp(conn, 500, ~s({"error":"boom"}))
    end)
  end

  defp stub_malformed do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{"content" => []})
    end)
  end

  defp start_conv(player, clone) do
    # Spawn unregistered so we can exercise the GenServer directly without
    # touching Horde (Horde is exercised in the public-API test).
    GenServer.start_link(Conversation, {player.id, clone})
  end

  defp setup_chat do
    Req.Test.set_req_test_to_shared(%{})
    room = insert_room()
    blueprint = insert_blueprint()
    clone = insert_clone(blueprint, room)
    player = register_and_place("alice", room)
    subscribe(player.id)
    %{room: room, blueprint: blueprint, clone: clone, player: player}
  end

  # --- Tests --------------------------------------------------------------

  describe "first :send" do
    setup [:setup_chat_fixture]

    defp setup_chat_fixture(_), do: setup_chat()

    test "returns {:ok, :new} and broadcasts :chat_new BEFORE returning", %{
      player: player,
      clone: clone
    } do
      stub_say("Hello, friend.")
      {:ok, pid} = start_conv(player, clone)

      assert {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})

      assert_receive %ChatSystemMessage{kind: :chat_new, npc_name: "Garrick"}
      assert_receive %ChatUtterance{kind: :chat_speech, text: "Hello, friend."}, 2_000
    end

    test "speech reply appends 2 entries to turns and broadcasts :chat_speech",
         %{player: player, clone: clone} do
      stub_say("Hello, friend.")
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})

      assert_receive %ChatUtterance{kind: :chat_speech, text: "Hello, friend."}, 2_000

      state = GenServer.call(pid, :get_state)
      assert length(state.turns) == 2
      refute state.pending?
    end

    test "emote reply broadcasts :chat_emote with mode :emote in history", %{
      player: player,
      clone: clone
    } do
      stub_emote("raises an eyebrow curiously")
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "Mars?"})

      assert_receive %ChatUtterance{
                       kind: :chat_emote,
                       text: "raises an eyebrow curiously"
                     },
                     2_000

      state = GenServer.call(pid, :get_state)
      [_player_turn, %{role: :npc, mode: :emote}] = state.turns
    end

    test "failed LLM call broadcasts :chat_fallback and does NOT add to history", %{
      player: player,
      clone: clone
    } do
      stub_500()
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})

      assert_receive %ChatSystemMessage{kind: :chat_fallback}, 2_000

      state = GenServer.call(pid, :get_state)
      assert state.turns == []
      refute state.pending?
      assert state.pending_player_message == nil
    end

    test "malformed LLM output is treated as failure", %{player: player, clone: clone} do
      stub_malformed()
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})

      assert_receive %ChatSystemMessage{kind: :chat_fallback}, 2_000

      state = GenServer.call(pid, :get_state)
      assert state.turns == []
    end
  end

  describe "in-flight lockout (FR-020)" do
    setup [:setup_chat_fixture]

    test "second :send while pending returns {:error, :still_thinking}",
         %{player: player, clone: clone} do
      # Stub: delay the LLM response so we can race a second send during it.
      Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
        Process.sleep(150)

        Req.Test.json(conn, %{
          "content" => [
            %{"type" => "tool_use", "name" => "say", "input" => %{"text" => "Hello."}}
          ]
        })
      end)

      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "first"})

      # Race a second send during the in-flight call.
      assert {:error, :still_thinking} = GenServer.call(pid, {:send, player.id, "second"})

      # Let the first call complete normally.
      assert_receive %ChatUtterance{kind: :chat_speech}, 2_000

      # After completion, a new send should succeed again.
      Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
        Req.Test.json(conn, %{
          "content" => [
            %{"type" => "tool_use", "name" => "say", "input" => %{"text" => "Sure."}}
          ]
        })
      end)

      assert {:ok, :continuing} = GenServer.call(pid, {:send, player.id, "third"})
    end
  end

  describe "multi-turn history (US2)" do
    setup [:setup_chat_fixture]

    test "second :send within window returns {:ok, :continuing} and broadcasts :chat_continuing",
         %{player: player, clone: clone} do
      stub_say("First.")
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})
      assert_receive %ChatSystemMessage{kind: :chat_new}
      assert_receive %ChatUtterance{kind: :chat_speech}, 2_000

      stub_say("Second.")
      {:ok, :continuing} = GenServer.call(pid, {:send, player.id, "more"})
      assert_receive %ChatSystemMessage{kind: :chat_continuing}
      assert_receive %ChatUtterance{kind: :chat_speech, text: "Second."}, 2_000

      state = GenServer.call(pid, :get_state)
      # Two full turn-pairs = 4 entries.
      assert length(state.turns) == 4
    end

    test "after the 21st turn pair, history caps at 20 pairs and oldest is dropped",
         %{player: player, clone: clone} do
      stub_say("ok")
      {:ok, pid} = start_conv(player, clone)

      for n <- 1..21 do
        {:ok, _} = GenServer.call(pid, {:send, player.id, "turn-#{n}"})
        # Wait for each reply before sending the next so the pending lockout
        # doesn't reject the second send.
        assert_receive %ChatUtterance{kind: :chat_speech}, 2_000
      end

      state = GenServer.call(pid, :get_state)
      # 20 pairs * 2 entries each.
      assert length(state.turns) == 40

      # The first turn ("turn-1") MUST have been dropped.
      texts = Enum.map(state.turns, & &1.text)
      refute "turn-1" in texts
      assert "turn-21" in texts
    end
  end

  describe "out-of-lore refusal rendering (US4)" do
    setup [:setup_chat_fixture]

    test "emote-mode refusal renders without quotes and without meta-references", %{
      player: player,
      clone: clone
    } do
      stub_emote("raises an eyebrow curiously")
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "what's the weather on Mars?"})

      assert_receive %ChatUtterance{
                       kind: :chat_emote,
                       text: "raises an eyebrow curiously",
                       npc_name: "Garrick"
                     } = msg,
                     2_000

      # Render through the game_components and verify no meta-reference leaks.
      assigns = %{entry: %{kind: msg.kind, actor_name: msg.npc_name, text: msg.text}}

      rendered =
        Phoenix.LiveViewTest.rendered_to_string(
          AgenticRealmsWeb.GameComponents.log_entry(assigns)
        )

      refute rendered =~ "as an AI"
      refute rendered =~ "as a language model"
      refute rendered =~ "I am a chatbot"
      # Visible content checks.
      assert rendered =~ "Garrick"
      assert rendered =~ "raises an eyebrow curiously"
      # Emote rendering MUST NOT add quote marks.
      refute rendered =~ "&ldquo;"
      refute rendered =~ "&rdquo;"
    end
  end

  describe "empty-lore NPC (US5)" do
    test "chat works and the system prompt uses the empty-lore fallback paragraph" do
      Req.Test.set_req_test_to_shared(%{})
      room = insert_room()
      blueprint = insert_blueprint()
      # Override the clone's lore to empty.
      clone = insert_clone(blueprint, room, lore: "")
      player = register_and_place("eve", room)
      subscribe(player.id)

      test_pid = self()

      Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
        # Capture the request body so we can assert on the system prompt.
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:llm_body, body})

        Req.Test.json(conn, %{
          "content" => [
            %{"type" => "tool_use", "name" => "emote", "input" => %{"text" => "shrugs"}}
          ]
        })
      end)

      {:ok, pid} = start_conv(player, clone)
      {:ok, :new} = GenServer.call(pid, {:send, player.id, "who are you?"})

      assert_receive %ChatUtterance{kind: :chat_emote, text: "shrugs"}, 2_000
      assert_receive {:llm_body, body}, 2_000

      assert body =~ "You have no detailed backstory of your own"
    end
  end

  describe "idle timeout" do
    setup [:setup_chat_fixture]

    test "after the configured idle window (200ms in tests), the process terminates",
         %{player: player, clone: clone} do
      stub_say("Hi.")
      {:ok, pid} = start_conv(player, clone)

      {:ok, :new} = GenServer.call(pid, {:send, player.id, "hi"})
      assert_receive %ChatUtterance{kind: :chat_speech}, 2_000

      ref = Process.monitor(pid)

      # Idle timeout is 200ms in test config — give some headroom.
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_500
    end
  end
end
