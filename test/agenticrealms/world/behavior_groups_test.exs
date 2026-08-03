defmodule AgenticRealms.World.BehaviorGroupsTest do
  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.Repo
  alias AgenticRealms.World.BehaviorGroups
  alias AgenticRealms.World.Schemas.BehaviorGroup

  @say %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "hi"}]}
  @bye %{"trigger" => "player_left", "actions" => [%{"type" => "say", "text" => "bye"}]}
  @emote %{"trigger" => "player_entered", "actions" => [%{"type" => "emote", "text" => "nods"}]}

  defp put_behavior_group(name, behaviors, applies_to \\ ["npc"]) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %BehaviorGroup{
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
      put_behavior_group("alpha", [@say])
      put_behavior_group("beta", [@emote])

      assert {:ok, [[@say], [@emote]]} = BehaviorGroups.resolve(["alpha", "beta"])
      assert {:ok, [[@emote], [@say]]} = BehaviorGroups.resolve(["beta", "alpha"])
    end

    test "rejects an unknown name" do
      put_behavior_group("alpha", [@say])

      assert {:error, {:unknown_behavior_group, "ghost"}} =
               BehaviorGroups.resolve(["alpha", "ghost"])
    end
  end

  describe "compose/2 — additive, attachment-ordered, lossless" do
    test "union of two behavior_groups ++ direct, in order, nothing dropped" do
      put_behavior_group("orc", [@emote])
      put_behavior_group("shopkeeper", [@say])
      direct = [@bye]

      assert {:ok, effective} = BehaviorGroups.compose(["orc", "shopkeeper"], direct)
      assert effective == [@emote, @say, @bye]
    end

    test "same-trigger behaviors from different sources are all retained" do
      put_behavior_group("a", [@say])
      put_behavior_group("b", [@emote])
      assert {:ok, [@say, @emote]} = BehaviorGroups.compose(["a", "b"], [])
    end

    test "unknown behavior_group propagates the error" do
      assert {:error, {:unknown_behavior_group, "nope"}} = BehaviorGroups.compose(["nope"], [])
    end
  end

  describe "validate_behaviors/1" do
    test "accepts the feature-009 vocabulary" do
      assert :ok = BehaviorGroups.validate_behaviors([@say, @bye, @emote])
    end

    test "rejects an unshipped trigger" do
      bad = [%{"trigger" => "on_examine", "actions" => [%{"type" => "say", "text" => "x"}]}]
      assert {:error, _} = BehaviorGroups.validate_behaviors(bad)
    end
  end

  describe "list_for/1 — cross-entity" do
    test "filters by applies_to" do
      put_behavior_group("npc_only", [@say], ["npc"])
      put_behavior_group("item_room", [@say], ["item", "room"])

      item_names = BehaviorGroups.list_for(:item) |> Enum.map(& &1.name)
      npc_names = BehaviorGroups.list_for(:npc) |> Enum.map(& &1.name)

      assert "item_room" in item_names
      refute "npc_only" in item_names
      assert "npc_only" in npc_names
      refute "item_room" in npc_names
    end
  end
end
