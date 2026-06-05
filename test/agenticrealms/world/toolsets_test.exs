defmodule AgenticRealms.World.ToolsetsTest do
  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Toolsets
  alias AgenticRealms.World.Schemas.Toolset

  @say %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "hi"}]}
  @bye %{"trigger" => "player_left", "actions" => [%{"type" => "say", "text" => "bye"}]}
  @emote %{"trigger" => "player_entered", "actions" => [%{"type" => "emote", "text" => "nods"}]}

  defp put_toolset(name, behaviors, applies_to \\ ["npc"]) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Toolset{
      name: name,
      behaviors: behaviors,
      applies_to: applies_to,
      inserted_at: now,
      updated_at: now
    }
    |> Repo.insert!()
  end

  describe "resolve/1" do
    test "resolves known names to behaviors in input order" do
      put_toolset("alpha", [@say])
      put_toolset("beta", [@emote])

      assert {:ok, [[@say], [@emote]]} = Toolsets.resolve(["alpha", "beta"])
      assert {:ok, [[@emote], [@say]]} = Toolsets.resolve(["beta", "alpha"])
    end

    test "rejects an unknown name (FR-018)" do
      put_toolset("alpha", [@say])
      assert {:error, {:unknown_toolset, "ghost"}} = Toolsets.resolve(["alpha", "ghost"])
    end
  end

  describe "compose/2 — additive, attachment-ordered, lossless (FR-016)" do
    test "union of two toolsets ++ direct, in order, nothing dropped" do
      put_toolset("orc", [@emote])
      put_toolset("shopkeeper", [@say])
      direct = [@bye]

      assert {:ok, effective} = Toolsets.compose(["orc", "shopkeeper"], direct)
      assert effective == [@emote, @say, @bye]
    end

    test "same-trigger behaviors from different sources are all retained" do
      put_toolset("a", [@say])
      put_toolset("b", [@emote])
      # both @say and @emote are player_entered → both kept
      assert {:ok, [@say, @emote]} = Toolsets.compose(["a", "b"], [])
    end

    test "unknown toolset propagates the error" do
      assert {:error, {:unknown_toolset, "nope"}} = Toolsets.compose(["nope"], [])
    end
  end

  describe "validate_behaviors/1 (FR-014)" do
    test "accepts the feature-009 vocabulary" do
      assert :ok = Toolsets.validate_behaviors([@say, @bye, @emote])
    end

    test "rejects an unshipped trigger" do
      bad = [%{"trigger" => "on_examine", "actions" => [%{"type" => "say", "text" => "x"}]}]
      assert {:error, _} = Toolsets.validate_behaviors(bad)
    end
  end

  describe "list_for/1 — cross-entity (FR-019)" do
    test "filters by applies_to" do
      put_toolset("npc_only", [@say], ["npc"])
      put_toolset("item_room", [@say], ["item", "room"])

      item_names = Toolsets.list_for(:item) |> Enum.map(& &1.name)
      npc_names = Toolsets.list_for(:npc) |> Enum.map(& &1.name)

      assert "item_room" in item_names
      refute "npc_only" in item_names
      assert "npc_only" in npc_names
      refute "item_room" in npc_names
    end
  end
end
