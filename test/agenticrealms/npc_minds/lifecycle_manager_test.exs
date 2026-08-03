defmodule AgenticRealms.NpcMinds.LifecycleManagerTest do
  @moduledoc "The lifecycle 'process manager' event handler."
  use ExUnit.Case, async: true

  alias AgenticRealms.NpcMinds.LifecycleManager
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityRemoved}
  alias AgenticRealms.World.ContainerRef

  @client AgenticRealms.NpcMinds.TemporalClient

  defp record_requests do
    parent = self()

    Req.Test.stub(@client, fn conn ->
      send(parent, {:temporal, conn.method, conn.request_path})
      Req.Test.json(conn, %{})
    end)
  end

  test "EntityCloned{kind: :npc} starts the NPC's workflow" do
    record_requests()

    assert :ok =
             LifecycleManager.handle(%EntityCloned{entity_id: "n1", kind: :npc, fields: %{}}, %{})

    assert_received {:temporal, "POST", "/api/v1/namespaces/default/workflows/npc-n1"}
  end

  test "EntityCloned{kind: :object} is ignored (no Temporal call)" do
    Req.Test.stub(@client, fn _conn ->
      flunk("Temporal must not be called for an object clone")
    end)

    assert :ok =
             LifecycleManager.handle(
               %EntityCloned{entity_id: "o1", kind: :object, fields: %{}},
               %{}
             )

    refute_received {:temporal, _, _}
  end

  test "EntityRemoved{kind: :npc} terminates the NPC's workflow" do
    record_requests()

    event = %EntityRemoved{
      entity_id: "n1",
      kind: :npc,
      from: ContainerRef.room("r1"),
      name: "Grik"
    }

    assert :ok = LifecycleManager.handle(event, %{})
    assert_received {:temporal, "POST", "/api/v1/namespaces/default/workflows/npc-n1/terminate"}
  end

  test "an unrelated event is ignored" do
    Req.Test.stub(@client, fn _conn -> flunk("Temporal must not be called") end)

    event = %EntityMoved{
      entity_id: "o1",
      from: ContainerRef.void(),
      to: ContainerRef.room("r1"),
      kind: :object
    }

    assert :ok = LifecycleManager.handle(event, %{})
  end
end
