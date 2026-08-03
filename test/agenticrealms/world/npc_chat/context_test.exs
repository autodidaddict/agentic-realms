defmodule AgenticRealms.World.NPCChat.ContextTest do
  @moduledoc """
  Unit tests for the chat context-builder.

  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCChat.Context

  defp snapshot do
    %{
      npc_name: "Garrick the Innkeeper",
      lore: "A wiry innkeeper.",
      room_name: "Stone Atrium",
      room_description: "A cool stone hall.",
      other_players: ["Bob"],
      objects: [%{name: "stone basin", short_description: "a worn stone basin"}],
      player_name: "Alice"
    }
  end

  describe "build_request/3" do
    test "with empty history, messages array has exactly the current user message" do
      req = Context.build_request(snapshot(), [], "Hello!")
      assert length(req["messages"]) == 1
      [user] = req["messages"]
      assert user["role"] == "user"
      assert user["content"] == "Hello!"
    end

    test "with one player + one NPC speech turn, messages array has 3 entries" do
      turns = [
        %{role: :player, text: "Hi"},
        %{role: :npc, text: "Hello, friend.", mode: :speech}
      ]

      req = Context.build_request(snapshot(), turns, "Tell me more.")
      assert length(req["messages"]) == 3

      [u1, a, u2] = req["messages"]
      assert u1["role"] == "user"
      assert u1["content"] == "Hi"
      assert a["role"] == "assistant"

      assert a["content"] == "Hello, friend."
      assert u2["content"] == "Tell me more."
    end

    test "NPC emote turn renders tagged so the LLM can distinguish gesture from speech" do
      turns = [
        %{role: :player, text: "What's wrong?"},
        %{role: :npc, text: "looks puzzled", mode: :emote}
      ]

      req = Context.build_request(snapshot(), turns, "Are you ok?")
      [_u, a, _u2] = req["messages"]
      assert a["content"] == "(emote: looks puzzled)"
    end

    test "request has the required top-level keys" do
      req = Context.build_request(snapshot(), [], "Hi")

      assert is_integer(req["max_tokens"])
      assert is_list(req["system"])
      assert is_list(req["tools"])
      assert req["tool_choice"] == %{"type" => "any"}
      assert is_list(req["messages"])
    end

    test "system block carries the cache_control marker on the text entry" do
      req = Context.build_request(snapshot(), [], "Hi")
      [system_block] = req["system"]

      assert system_block["type"] == "text"
      assert system_block["cache_control"] == %{"type" => "ephemeral"}
      assert is_binary(system_block["text"])
    end

    test "system prompt contains the room description and player name" do
      req = Context.build_request(snapshot(), [], "Hi")
      [system_block] = req["system"]
      assert system_block["text"] =~ "A cool stone hall."
      assert system_block["text"] =~ "Alice is speaking with you here."
    end
  end
end
