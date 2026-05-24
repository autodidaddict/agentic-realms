defmodule AgenticRealms.World.Schemas.NPCCloneTest do
  @moduledoc """
  Unit tests for the `Schemas.NPCClone.debug_id/1` LPMud-style identity
  helper (feature 008 FR-011).
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Schemas.NPCClone

  describe "debug_id/1" do
    test "renders <name>#<serial> for a simple name" do
      clone = %NPCClone{name: "Garrick", serial: 1}
      assert NPCClone.debug_id(clone) == "Garrick#1"
    end

    test "renders <name>#<serial> for a multi-word name" do
      clone = %NPCClone{name: "Garrick the Innkeeper", serial: 7}
      assert NPCClone.debug_id(clone) == "Garrick the Innkeeper#7"
    end

    test "preserves special characters in the name" do
      clone = %NPCClone{name: "Brother O'Malley", serial: 12}
      assert NPCClone.debug_id(clone) == "Brother O'Malley#12"
    end

    test "renders larger serials correctly" do
      clone = %NPCClone{name: "Mass-produced Goblin", serial: 9999}
      assert NPCClone.debug_id(clone) == "Mass-produced Goblin#9999"
    end
  end
end
