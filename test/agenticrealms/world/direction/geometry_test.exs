defmodule AgenticRealms.World.Direction.GeometryTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Direction.Geometry

  # A test "room" is just any map that exposes :map_x, :map_y, :elevation.
  defp room(x, y, elev \\ 0), do: %{map_x: x, map_y: y, elevation: elev}
  defp off_map, do: %{map_x: nil, map_y: nil, elevation: 0}

  describe "delta/1" do
    test "cardinal deltas use screen coords (y grows downward)" do
      assert {:planar, {0, -1}} = Geometry.delta(:north)
      assert {:planar, {0, 1}} = Geometry.delta(:south)
      assert {:planar, {1, 0}} = Geometry.delta(:east)
      assert {:planar, {-1, 0}} = Geometry.delta(:west)
    end

    test "diagonal deltas" do
      assert {:planar, {1, -1}} = Geometry.delta(:northeast)
      assert {:planar, {-1, -1}} = Geometry.delta(:northwest)
      assert {:planar, {1, 1}} = Geometry.delta(:southeast)
      assert {:planar, {-1, 1}} = Geometry.delta(:southwest)
    end

    test "vertical deltas" do
      assert {:vertical, 1} = Geometry.delta(:up)
      assert {:vertical, -1} = Geometry.delta(:down)
    end
  end

  describe "consistent?/3 — off-map skip" do
    test "source off-map → :ok (any direction, any target)" do
      assert :ok = Geometry.consistent?(:north, off_map(), room(5, 5))
      assert :ok = Geometry.consistent?(:up, off_map(), room(0, 0, 7))
      assert :ok = Geometry.consistent?(:northeast, off_map(), room(0, 0, 0))
    end

    test "target off-map → :ok" do
      assert :ok = Geometry.consistent?(:north, room(0, 0), off_map())
      assert :ok = Geometry.consistent?(:up, room(3, 3, 0), off_map())
    end

    test "both off-map → :ok" do
      assert :ok = Geometry.consistent?(:north, off_map(), off_map())
    end
  end

  describe "consistent?/3 — cardinals (distance 1)" do
    test "north accepts target one cell north" do
      assert :ok = Geometry.consistent?(:north, room(0, 0), room(0, -1))
    end

    test "south accepts target one cell south" do
      assert :ok = Geometry.consistent?(:south, room(0, 0), room(0, 1))
    end

    test "east accepts target one cell east" do
      assert :ok = Geometry.consistent?(:east, room(0, 0), room(1, 0))
    end

    test "west accepts target one cell west" do
      assert :ok = Geometry.consistent?(:west, room(0, 0), room(-1, 0))
    end
  end

  describe "consistent?/3 — cardinals (flexible distance)" do
    test "north accepts distance > 1 (bridge / long corridor)" do
      assert :ok = Geometry.consistent?(:north, room(0, 0), room(0, -5))
    end

    test "east accepts distance > 1" do
      assert :ok = Geometry.consistent?(:east, room(0, 0), room(10, 0))
    end
  end

  describe "consistent?/3 — diagonals" do
    test "northeast accepts equal |Δx| and |Δy| with correct signs" do
      assert :ok = Geometry.consistent?(:northeast, room(0, 0), room(1, -1))
      assert :ok = Geometry.consistent?(:northeast, room(0, 0), room(3, -3))
    end

    test "northwest accepts" do
      assert :ok = Geometry.consistent?(:northwest, room(0, 0), room(-2, -2))
    end

    test "southeast accepts" do
      assert :ok = Geometry.consistent?(:southeast, room(0, 0), room(4, 4))
    end

    test "southwest accepts" do
      assert :ok = Geometry.consistent?(:southwest, room(0, 0), room(-3, 3))
    end
  end

  describe "consistent?/3 — vertical" do
    test "up accepts target at same (x, y) with higher elevation" do
      assert :ok = Geometry.consistent?(:up, room(2, 3, 0), room(2, 3, 1))
      assert :ok = Geometry.consistent?(:up, room(2, 3, 0), room(2, 3, 5))
    end

    test "down accepts target at same (x, y) with lower elevation" do
      assert :ok = Geometry.consistent?(:down, room(0, 0, 3), room(0, 0, 0))
    end
  end

  describe "consistent?/3 — planar rejects" do
    test "elevation mismatch on planar exit" do
      assert {:error, :elevation_mismatch_for_planar_exit} =
               Geometry.consistent?(:north, room(0, 0, 0), room(0, -1, 1))
    end

    test "off-axis cardinal" do
      # north requires Δx == 0, but target.x = 1
      assert {:error, :off_axis_for_direction} =
               Geometry.consistent?(:north, room(0, 0), room(1, -1))
    end

    test "wrong-sign cardinal" do
      # north requires target.y < source.y; (0, 1) is south
      assert {:error, :off_axis_for_direction} =
               Geometry.consistent?(:north, room(0, 0), room(0, 1))
    end

    test "zero-distance cardinal (target == source)" do
      assert {:error, :off_axis_for_direction} =
               Geometry.consistent?(:north, room(0, 0), room(0, 0))
    end

    test "diagonal with unequal Δx / Δy magnitudes" do
      assert {:error, :off_axis_for_direction} =
               Geometry.consistent?(:northeast, room(0, 0), room(2, -1))
    end

    test "diagonal with wrong-sign component" do
      # northeast requires Δx > 0 and Δy < 0; (-1, -1) has Δx < 0
      assert {:error, :off_axis_for_direction} =
               Geometry.consistent?(:northeast, room(0, 0), room(-1, -1))
    end
  end

  describe "consistent?/3 — vertical rejects" do
    test "horizontal offset on vertical exit" do
      assert {:error, :horizontal_offset_for_vertical_exit} =
               Geometry.consistent?(:up, room(0, 0, 0), room(1, 0, 1))
    end

    test "wrong vertical direction" do
      # up requires target.elevation > source.elevation
      assert {:error, :wrong_vertical_direction} =
               Geometry.consistent?(:up, room(0, 0, 1), room(0, 0, 0))
    end

    test "zero elevation change on vertical exit" do
      assert {:error, :no_elevation_change_for_vertical_exit} =
               Geometry.consistent?(:up, room(0, 0, 0), room(0, 0, 0))
    end
  end

  describe "unit_vector/1" do
    test "cardinals" do
      {nx, ny} = Geometry.unit_vector(:north)
      assert nx == 0.0 and ny == -1.0
      {sx, sy} = Geometry.unit_vector(:south)
      assert sx == 0.0 and sy == 1.0
      {ex, ey} = Geometry.unit_vector(:east)
      assert ex == 1.0 and ey == 0.0
      {wx, wy} = Geometry.unit_vector(:west)
      assert wx == -1.0 and wy == 0.0
    end

    test "diagonals are unit length in screen coords" do
      {dx, dy} = Geometry.unit_vector(:northeast)
      assert_in_delta :math.sqrt(dx * dx + dy * dy), 1.0, 1.0e-9
      assert dx > 0
      assert dy < 0
    end

    test "raises for vertical directions" do
      assert_raise ArgumentError, fn -> Geometry.unit_vector(:up) end
      assert_raise ArgumentError, fn -> Geometry.unit_vector(:down) end
    end
  end

  describe "planar?/1" do
    test "true for compass directions" do
      for d <- [:north, :south, :east, :west, :northeast, :northwest, :southeast, :southwest] do
        assert Geometry.planar?(d), "expected #{d} to be planar"
      end
    end

    test "false for verticals" do
      refute Geometry.planar?(:up)
      refute Geometry.planar?(:down)
    end
  end
end
