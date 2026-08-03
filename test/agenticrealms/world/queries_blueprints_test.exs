defmodule AgenticRealms.World.QueriesBlueprintsTest do
  @moduledoc """
  The unified blueprint registry query lists both kinds and
  filters by kind.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.Blueprint

  defp put_blueprint(id, kind, name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Blueprint{
      id: id,
      kind: kind,
      name: name,
      short_description: "short",
      long_description: "long",
      revision: 1,
      inserted_at: now,
      updated_at: now
    })
  end

  test "list_blueprints/0 unions both kinds; list_blueprints/1 filters by kind" do
    suffix = System.unique_integer([:positive])
    obj = "obj_#{suffix}"
    npc = "npc_#{suffix}"

    put_blueprint(obj, "object", "An Object #{suffix}")
    put_blueprint(npc, "npc", "An NPC #{suffix}")

    all_ids = Queries.list_blueprints() |> Enum.map(& &1.id)
    assert obj in all_ids
    assert npc in all_ids

    assert Enum.all?(Queries.list_blueprints(), &(&1.kind in ["object", "npc"]))

    object_ids = Queries.list_blueprints("object") |> Enum.map(& &1.id)
    npc_ids = Queries.list_blueprints("npc") |> Enum.map(& &1.id)

    assert obj in object_ids
    refute npc in object_ids
    assert npc in npc_ids
    refute obj in npc_ids
  end
end
