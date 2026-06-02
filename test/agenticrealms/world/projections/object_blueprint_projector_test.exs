defmodule AgenticRealms.World.Projections.ObjectBlueprintProjectorTest do
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Events.ObjectBlueprintCreated
  alias AgenticRealms.World.Projections.ObjectBlueprintProjector
  alias AgenticRealms.World.Schemas.ObjectBlueprint

  @event %ObjectBlueprintCreated{
    blueprint_id: "test_chest",
    kind: "object",
    name: "test chest",
    short_description: "a test chest",
    long_description: "An exhaustively tested brass chest.",
    fixed: true,
    revision: 1,
    version: 1
  }

  test "handle/2 inserts a row at revision 1 with the event payload" do
    :ok = ObjectBlueprintProjector.handle(@event, %{})

    assert %ObjectBlueprint{
             id: "test_chest",
             kind: "object",
             name: "test chest",
             short_description: "a test chest",
             long_description: "An exhaustively tested brass chest.",
             fixed: true,
             revision: 1
           } = Repo.get(ObjectBlueprint, "test_chest")
  end

  test "handle/2 is idempotent against replay (on_conflict: :nothing)" do
    :ok = ObjectBlueprintProjector.handle(@event, %{})
    :ok = ObjectBlueprintProjector.handle(@event, %{})

    rows = Repo.all(ObjectBlueprint) |> Enum.filter(&(&1.id == "test_chest"))
    assert length(rows) == 1
  end
end
