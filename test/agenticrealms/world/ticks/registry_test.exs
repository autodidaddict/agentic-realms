defmodule AgenticRealms.World.Ticks.RegistryTest do
  @moduledoc """
  Unit tests for the per-room tick Scheduler registry.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Schemas.Room
  alias AgenticRealms.World.Ticks.{Registry, Supervisor, Scheduler}

  defp insert_room do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  describe "via_tuple/1" do
    test "returns a three-tuple shape" do
      assert {:via, Horde.Registry, {Registry, "room-1"}} = Registry.via_tuple("room-1")
    end
  end

  describe "lookup/1" do
    test "returns :error for an unregistered room" do
      assert :error = Registry.lookup("nonexistent-room-id")
    end

    test "returns {:ok, pid} after Supervisor.find_or_start/1" do
      room = insert_room()

      assert {:ok, pid} = Supervisor.find_or_start(room.id)
      assert is_pid(pid)
      assert {:ok, ^pid} = Registry.lookup(room.id)

      :ok = Supervisor.terminate(room.id)
    end

    test "find_or_start/1 is idempotent" do
      room = insert_room()

      assert {:ok, pid1} = Supervisor.find_or_start(room.id)
      assert {:ok, pid2} = Supervisor.find_or_start(room.id)
      assert pid1 == pid2

      :ok = Supervisor.terminate(room.id)
    end
  end

  describe "Supervisor" do
    test "terminate/1 returns :error for an unstarted scheduler" do
      assert {:error, :not_found} = Supervisor.terminate("never-started")
    end

    test "a terminated scheduler is removed from the registry" do
      room = insert_room()

      {:ok, _pid} = Supervisor.find_or_start(room.id)
      :ok = Supervisor.terminate(room.id)

      Process.sleep(50)
      assert :error = Registry.lookup(room.id)
    end
  end

  defp _used_in_setup, do: Scheduler
end
