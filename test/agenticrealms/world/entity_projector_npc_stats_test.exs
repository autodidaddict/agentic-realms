defmodule AgenticRealms.World.EntityProjectorNpcStatsTest do
  @moduledoc """
  Feature 019 — EntityCloned{:npc} freezes the blueprint's stats onto the
  npc_clones row. Calls the projector's `handle/2` directly (a pure Repo write;
  no command dispatch), so no Commanded chain is needed.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Projections.EntityProjector
  alias AgenticRealms.World.Events.EntityCloned
  alias AgenticRealms.World.Schemas.NPCClone

  defp clone_fields(overrides) do
    Map.merge(
      %{
        blueprint_id: nil,
        name: "Test Ogre",
        short_description: "an ogre",
        long_description: "A big ogre.",
        behaviors: [],
        direct_behaviors: [],
        behavior_groups: [],
        lore: "",
        fixed: false,
        str: 16,
        dex: 8,
        con: 15,
        int: 6,
        wis: 7,
        cha: 5,
        level: 4,
        hp: 30,
        max_hp: 30,
        mana: 12,
        max_mana: 12
      },
      overrides
    )
  end

  defp clone!(overrides) do
    id = Ecto.UUID.generate()

    :ok =
      EntityProjector.handle(
        %EntityCloned{entity_id: id, kind: :npc, fields: clone_fields(overrides)},
        %{}
      )

    Repo.get!(NPCClone, id)
  end

  test "frozen stat columns are written; current hp/mana start at max" do
    clone = clone!(%{name: "Ogre One"})

    assert clone.str == 16
    assert clone.dex == 8
    assert clone.con == 15
    assert clone.level == 4
    assert clone.hp == 30
    assert clone.max_hp == 30
    assert clone.mana == 12
    assert clone.max_mana == 12
  end

  test "two clones of the same blueprint carry independent hitpoints" do
    a = clone!(%{name: "Ogre A"})
    b = clone!(%{name: "Ogre B", hp: 5})

    assert a.hp == 30
    assert b.hp == 5
  end

  test "a field map without stats falls back to defaults" do
    id = Ecto.UUID.generate()

    bare = %{
      blueprint_id: nil,
      name: "Bare NPC",
      short_description: "s",
      long_description: "l",
      behaviors: [],
      direct_behaviors: [],
      behavior_groups: [],
      lore: "",
      fixed: false
    }

    :ok = EntityProjector.handle(%EntityCloned{entity_id: id, kind: :npc, fields: bare}, %{})
    clone = Repo.get!(NPCClone, id)

    assert clone.str == 12
    assert clone.level == 1
    assert clone.hp == 10
    assert clone.max_hp == 10
  end
end
