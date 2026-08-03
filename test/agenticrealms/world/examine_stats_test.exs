defmodule AgenticRealms.World.ExamineStatsTest do
  @moduledoc """
  Feature 019 US3 — examining a player or NPC enriches the Match with a
  qualitative health tier and a relative-power phrase; self omits the power
  phrase. Inserts read-model rows directly (pure read), mirroring ExamineTest.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Examine
  alias AgenticRealms.World.Examine.Match
  alias AgenticRealms.DataCase
  alias AgenticRealms.World.Schemas.{Room, PlayerState, Blueprint, NPCClone}
  alias AgenticRealmsWeb.Presence

  defp register(name) do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "#{name}_#{suffix}", password: "pw12345678"})
    p
  end

  defp room! do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Arena",
      description: "d",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp place(player, room, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        PlayerState,
        [player_id: player.id, current_room_id: room.id] ++
          DataCase.character_columns(
            Keyword.put_new(Enum.to_list(attrs), :character_name, player.username)
          )
      )
    )
  end

  defp online(player) do
    {:ok, _} = Presence.track_player(self(), player.id, player.username)
    Process.sleep(20)
    :ok
  end

  defp npc!(room, name, attrs) do
    bp_id = "bp_#{System.unique_integer([:positive])}"

    Repo.insert!(%Blueprint{
      id: bp_id,
      kind: "npc",
      name: name,
      short_description: "s",
      long_description: "A foe."
    })

    Repo.insert!(
      struct(
        %NPCClone{
          id: Ecto.UUID.generate(),
          blueprint_id: bp_id,
          name: name,
          short_description: "s",
          long_description: "A foe.",
          room_id: room.id
        },
        attrs
      )
    )
  end

  setup do
    alice = register("alice")
    room = room!()
    place(alice, room)
    online(alice)
    %{alice: alice, room: room}
  end

  test "examining a same-level, full-health NPC yields the top tiers", %{alice: alice, room: room} do
    npc!(room, "grumbol", %{level: 1, hp: 10, max_hp: 10})

    assert {:ok,
            %Match{
              target_kind: :npc,
              health_tier: "Very healthy",
              power_phrase: "about as powerful"
            }} =
             Examine.examine(alice.id, "grumbol")
  end

  test "a far higher-level NPC is 'too powerful to even compare'", %{alice: alice, room: room} do
    npc!(room, "titan", %{level: 9, hp: 50, max_hp: 50})

    assert {:ok, %Match{power_phrase: "too powerful to even compare"}} =
             Examine.examine(alice.id, "titan")
  end

  test "a wounded NPC reports a low health tier", %{alice: alice, room: room} do
    npc!(room, "wretch", %{level: 1, hp: 2, max_hp: 10})

    assert {:ok, %Match{health_tier: "Very Weakened"}} = Examine.examine(alice.id, "wretch")
  end

  test "examining another player enriches with health + power", %{alice: alice, room: room} do
    bob = register("bob")
    place(bob, room, %{level: 6, hp: 30, max_hp: 30})
    online(bob)

    assert {:ok, %Match{target_kind: :player, health_tier: "Very healthy", power_phrase: pp}} =
             Examine.examine(alice.id, String.downcase(bob.username))

    assert pp == "too powerful to even compare"
  end

  test "self-examination omits the relative-power phrase", %{alice: alice} do
    assert {:ok, %Match{target_kind: :player, power_phrase: nil}} =
             Examine.examine(alice.id, "me")
  end
end
