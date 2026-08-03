defmodule AgenticRealms.World.Schemas.NPCCloneTest do
  @moduledoc """
  Unit tests for the `Schemas.NPCClone.debug_id/1` LPMud-style identity
  helper. Since `serial` was dropped, the debug
  identity is `<name>#<entity_id>`.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Schemas.NPCClone

  describe "debug_id/1" do
    test "renders <name>#<id> for a simple name" do
      clone = %NPCClone{name: "Garrick", id: "abc123"}
      assert NPCClone.debug_id(clone) == "Garrick#abc123"
    end

    test "renders <name>#<id> for a multi-word name" do
      clone = %NPCClone{name: "Garrick the Innkeeper", id: "uuid-7"}
      assert NPCClone.debug_id(clone) == "Garrick the Innkeeper#uuid-7"
    end

    test "preserves special characters in the name" do
      clone = %NPCClone{name: "Brother O'Malley", id: "id-12"}
      assert NPCClone.debug_id(clone) == "Brother O'Malley#id-12"
    end
  end
end
