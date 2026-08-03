defmodule AgenticRealms.NpcMinds.ReconcilerTest do
  @moduledoc "The reconciler's pure live↔running diff."
  use ExUnit.Case, async: true

  alias AgenticRealms.NpcMinds.Reconciler

  test "diff starts live-but-not-running and terminates running-but-not-live" do
    live = ["a", "b", "c"]
    running = ["b", "c", "d"]

    %{to_start: to_start, to_terminate: to_terminate} = Reconciler.diff(live, running)

    assert Enum.sort(to_start) == ["a"]
    assert Enum.sort(to_terminate) == ["d"]
  end

  test "diff is empty when live and running match" do
    assert %{to_start: [], to_terminate: []} = Reconciler.diff(["x", "y"], ["y", "x"])
  end

  test "all live start when nothing is running" do
    assert %{to_start: to_start, to_terminate: []} = Reconciler.diff(["a", "b"], [])
    assert Enum.sort(to_start) == ["a", "b"]
  end

  test "all running terminate when nothing is live" do
    assert %{to_start: [], to_terminate: to_terminate} = Reconciler.diff([], ["a", "b"])
    assert Enum.sort(to_terminate) == ["a", "b"]
  end
end
