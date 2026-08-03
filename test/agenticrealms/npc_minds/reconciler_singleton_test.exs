defmodule AgenticRealms.NpcMinds.ReconcilerSingletonTest do
  @moduledoc "Feature 018 — the reconciler runs as a single Horde-registered cluster singleton."
  use ExUnit.Case, async: false

  alias AgenticRealms.NpcMinds.{Registry, Supervisor}

  setup do
    start_supervised!(Registry)
    start_supervised!(Supervisor)
    :ok
  end

  test "ensure_reconciler starts exactly one reconciler and is idempotent" do
    assert {:ok, pid} = Supervisor.ensure_reconciler()
    assert Process.alive?(pid)

    assert {:ok, ^pid} = Supervisor.ensure_reconciler()
  end

  test "the singleton is discoverable via the Horde registry" do
    {:ok, pid} = Supervisor.ensure_reconciler()

    assert eventually(fn -> Registry.lookup() == {:ok, pid} end)
  end

  defp eventually(_fun, 0), do: false

  defp eventually(fun, retries) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, retries - 1)
    end
  end

  defp eventually(fun), do: eventually(fun, 50)
end
