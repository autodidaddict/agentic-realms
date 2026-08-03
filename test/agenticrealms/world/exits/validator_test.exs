defmodule AgenticRealms.World.Exits.ValidatorTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Exits.Validator

  defp room(x, y, elev \\ 0), do: %{map_x: x, map_y: y, elevation: elev, region_id: "r-1"}

  defp room_in(region_id, x, y, elev \\ 0),
    do: %{map_x: x, map_y: y, elevation: elev, region_id: region_id}

  defp off_map, do: %{map_x: nil, map_y: nil, elevation: 0, region_id: "r-1"}

  describe "accept matrix" do
    test "cardinals at distance 1" do
      assert :ok = Validator.consistent?(:north, room(0, 0), room(0, -1))
      assert :ok = Validator.consistent?(:south, room(0, 0), room(0, 1))
      assert :ok = Validator.consistent?(:east, room(0, 0), room(1, 0))
      assert :ok = Validator.consistent?(:west, room(0, 0), room(-1, 0))
    end

    test "cardinals at distance > 1 (bridges)" do
      assert :ok = Validator.consistent?(:north, room(0, 0), room(0, -7))
      assert :ok = Validator.consistent?(:east, room(0, 0), room(12, 0))
    end

    test "diagonals" do
      assert :ok = Validator.consistent?(:northeast, room(0, 0), room(1, -1))
      assert :ok = Validator.consistent?(:northwest, room(0, 0), room(-2, -2))
      assert :ok = Validator.consistent?(:southeast, room(0, 0), room(3, 3))
      assert :ok = Validator.consistent?(:southwest, room(0, 0), room(-4, 4))
    end

    test "verticals" do
      assert :ok = Validator.consistent?(:up, room(0, 0, 0), room(0, 0, 1))
      assert :ok = Validator.consistent?(:down, room(0, 0, 5), room(0, 0, 0))
    end

    test "off-map skip — source" do
      assert :ok = Validator.consistent?(:north, off_map(), room(99, 99))
      assert :ok = Validator.consistent?(:up, off_map(), room(0, 0, 100))
    end

    test "off-map skip — target" do
      assert :ok = Validator.consistent?(:east, room(0, 0), off_map())
    end

    test "off-map skip — both" do
      assert :ok = Validator.consistent?(:northwest, off_map(), off_map())
    end

    test "cross-region skip — different region_ids bypass geometry" do
      assert :ok =
               Validator.consistent?(
                 :east,
                 room_in("blackmire", 3, 2),
                 room_in("hollowvale", 0, 0)
               )
    end

    test "same-region exits still get the geometry check" do
      assert {:error, {:exit_geometry_violation, _}} =
               Validator.consistent?(
                 :east,
                 room_in("blackmire", 3, 2),
                 room_in("blackmire", 0, 0)
               )
    end
  end

  describe "reject matrix" do
    test "planar elevation mismatch" do
      assert {:error, {:exit_geometry_violation, :elevation_mismatch_for_planar_exit}} =
               Validator.consistent?(:north, room(0, 0, 0), room(0, -1, 1))
    end

    test "off-axis cardinal" do
      assert {:error, {:exit_geometry_violation, :off_axis_for_direction}} =
               Validator.consistent?(:north, room(0, 0), room(1, -1))
    end

    test "wrong-sign cardinal" do
      assert {:error, {:exit_geometry_violation, :off_axis_for_direction}} =
               Validator.consistent?(:east, room(0, 0), room(-1, 0))
    end

    test "diagonal with unequal axes" do
      assert {:error, {:exit_geometry_violation, :off_axis_for_direction}} =
               Validator.consistent?(:northeast, room(0, 0), room(3, -1))
    end

    test "horizontal offset on vertical exit" do
      assert {:error, {:exit_geometry_violation, :horizontal_offset_for_vertical_exit}} =
               Validator.consistent?(:up, room(0, 0, 0), room(1, 0, 1))
    end

    test "wrong vertical direction" do
      assert {:error, {:exit_geometry_violation, :wrong_vertical_direction}} =
               Validator.consistent?(:up, room(0, 0, 2), room(0, 0, 1))
    end

    test "zero elevation change on vertical exit" do
      assert {:error, {:exit_geometry_violation, :no_elevation_change_for_vertical_exit}} =
               Validator.consistent?(:down, room(3, 3, 0), room(3, 3, 0))
    end
  end

  describe "generated matrix — every planar direction round-trips" do
    @directions [:north, :south, :east, :west, :northeast, :northwest, :southeast, :southwest]

    @deltas %{
      north: {0, -1},
      south: {0, 1},
      east: {1, 0},
      west: {-1, 0},
      northeast: {1, -1},
      northwest: {-1, -1},
      southeast: {1, 1},
      southwest: {-1, 1}
    }

    for dir <- @directions do
      test "#{dir} accepts the matching unit step" do
        {dx, dy} = Map.fetch!(@deltas, unquote(dir))
        assert :ok = Validator.consistent?(unquote(dir), room(0, 0), room(dx, dy))
      end

      test "#{dir} accepts an n-cell step along its axis" do
        {dx, dy} = Map.fetch!(@deltas, unquote(dir))
        assert :ok = Validator.consistent?(unquote(dir), room(0, 0), room(dx * 5, dy * 5))
      end
    end
  end
end
