defmodule AgenticRealms.World.Transient.GeneratorTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Transient.Generator

  describe "generate/2" do
    test "produces a well-formed transient region spec" do
      owner = 42
      source = Ecto.UUID.generate()
      spec = Generator.generate(owner, source)

      assert is_binary(spec.region_id)
      assert spec.provision_owner_id == owner
      assert spec.source_room_id == source
      assert is_binary(spec.origin_room_id)
      assert length(spec.rooms) == 3

      room_ids = Enum.map(spec.rooms, & &1.room_id)
      assert spec.origin_room_id in room_ids

      # Owner-only rift entry: source -> origin, scoped to the owner.
      assert spec.entry_exit.direction == :rift
      assert spec.entry_exit.source_room_id == source
      assert spec.entry_exit.target_room_id == spec.origin_room_id
      assert spec.entry_exit.visible_to_user_id == owner

      # A rift return exit leads out of the origin back to the source room.
      assert Enum.any?(spec.intra_exits, fn e ->
               e.from == spec.origin_room_id and e.direction == :rift and e.to == source
             end)

      # Every intra exit references a known room (or the source, for the return).
      known = MapSet.new([source | room_ids])

      assert Enum.all?(spec.intra_exits, fn e ->
               MapSet.member?(known, e.from) and MapSet.member?(known, e.to)
             end)
    end

    test "mints fresh ids on each call so regions are distinct" do
      s = Ecto.UUID.generate()
      a = Generator.generate(1, s)
      b = Generator.generate(1, s)

      assert a.region_id != b.region_id
      assert a.origin_room_id != b.origin_room_id
      # Region names carry a unique index — must differ per region.
      assert a.name != b.name
    end
  end
end
