defmodule AgenticRealms.World.ContainerRefTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.ContainerRef

  describe "constructors + type predicates" do
    test "helpers build the right typed refs" do
      assert %ContainerRef{type: :void, id: nil} = ContainerRef.void()
      assert %ContainerRef{type: :room, id: "r1"} = ContainerRef.room("r1")
      assert %ContainerRef{type: :player, id: 7} = ContainerRef.player(7)
      assert %ContainerRef{type: :npc, id: "n1"} = ContainerRef.npc("n1")
    end

    test "types/valid_type? cover exactly void/room/player/npc" do
      assert ContainerRef.types() == [:void, :room, :player, :npc]
      for t <- [:void, :room, :player, :npc], do: assert(ContainerRef.valid_type?(t))
      refute ContainerRef.valid_type?(:bogus)
    end
  end

  describe "valid?/1 — void⇔nil-id pairing" do
    test "void must have nil id; others must have a non-nil id" do
      assert ContainerRef.valid?(ContainerRef.void())
      refute ContainerRef.valid?(%ContainerRef{type: :void, id: "oops"})
      assert ContainerRef.valid?(ContainerRef.room("r1"))
      refute ContainerRef.valid?(%ContainerRef{type: :room, id: nil})
    end
  end

  describe "to_map/from_map round-trip" do
    test "struct → map → struct" do
      ref = ContainerRef.room("r1")
      assert ContainerRef.to_map(ref) == %{"type" => "room", "id" => "r1"}
      assert ContainerRef.from_map(ContainerRef.to_map(ref)) == ref
    end

    test "from_map tolerates struct passthrough, string-keyed and atom-keyed maps" do
      ref = ContainerRef.player(7)
      assert ContainerRef.from_map(ref) == ref
      assert ContainerRef.from_map(%{"type" => "player", "id" => 7}) == ref
      assert ContainerRef.from_map(%{type: :player, id: 7}) == ref
    end

    test "void round-trips with a nil id" do
      assert ContainerRef.from_map(%{"type" => "void", "id" => nil}) == ContainerRef.void()
    end
  end

  describe "equal?/2" do
    test "compares across struct and map forms" do
      assert ContainerRef.equal?(ContainerRef.room("r1"), %{"type" => "room", "id" => "r1"})
      refute ContainerRef.equal?(ContainerRef.room("r1"), ContainerRef.room("r2"))
      refute ContainerRef.equal?(ContainerRef.room("r1"), ContainerRef.player("r1"))
      assert ContainerRef.equal?(ContainerRef.void(), %{type: :void, id: nil})
    end
  end
end
