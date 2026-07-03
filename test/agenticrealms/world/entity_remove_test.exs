defmodule AgenticRealms.World.EntityRemoveTest do
  @moduledoc "Feature 018 — RemoveEntity execute/apply on the Entity aggregate."
  use ExUnit.Case, async: true

  alias AgenticRealms.World.{Entity, ContainerRef}
  alias AgenticRealms.World.Commands.RemoveEntity
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityRemoved}

  defp npc_in_room(id \\ "n1", room \\ "r1", name \\ "Grik") do
    %Entity{}
    |> Entity.apply(%EntityCloned{entity_id: id, kind: :npc, fields: %{name: name}})
    |> Entity.apply(%EntityMoved{
      entity_id: id,
      from: ContainerRef.void(),
      to: ContainerRef.room(room)
    })
  end

  test "removing an existing entity emits EntityRemoved with kind, from, and name" do
    assert %EntityRemoved{
             entity_id: "n1",
             kind: :npc,
             name: "Grik",
             from: %ContainerRef{type: :room, id: "r1"}
           } = Entity.execute(npc_in_room(), %RemoveEntity{entity_id: "n1"})
  end

  test "removing an uncreated entity → :not_found" do
    assert {:error, :not_found} = Entity.execute(%Entity{}, %RemoveEntity{entity_id: "n1"})
  end

  test "removing an already-removed entity → :not_found (idempotent)" do
    removed =
      Entity.apply(npc_in_room(), %EntityRemoved{
        entity_id: "n1",
        kind: :npc,
        from: ContainerRef.room("r1"),
        name: "Grik"
      })

    assert removed.removed == true
    assert {:error, :not_found} = Entity.execute(removed, %RemoveEntity{entity_id: "n1"})
  end

  test "name is tracked from clone fields even with string keys (post-replay)" do
    state =
      Entity.apply(%Entity{}, %EntityCloned{
        entity_id: "n2",
        kind: :npc,
        fields: %{"name" => "Replayed"}
      })

    assert %EntityRemoved{name: "Replayed"} =
             Entity.execute(state, %RemoveEntity{entity_id: "n2"})
  end
end
