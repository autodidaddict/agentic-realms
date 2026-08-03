defmodule AgenticRealms.World.Ticks.SchedulerResilienceTest do
  @moduledoc """
  `Ticks.Scheduler` must survive a database it cannot reach, for the same
  reason `Ticks.Lifecycle` must: it is long-lived, supervised, and queries on
  startup and on scope changes. Dying costs a restart back into the query that
  killed it, not one stale scope entry.

  Started against a private, unregistered instance so nothing here touches the
  Horde registry or any scheduler another test is relying on. `async: true` is
  what makes the database genuinely unreachable — see the note on
  `start_isolated_scheduler/0`.
  """

  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.World.Ticks.Scheduler
  alias AgenticRealms.World.UIEvents.RoomNPCArrived

  # A Scheduler with no route to a connection.
  #
  # Started from a bare `spawn/1`, which sets neither `$callers` nor
  # `$ancestors` back to this test — so the sandbox has no owner to resolve and
  # every query fails. Starting it from the test process would inherit
  # ownership through `$callers` and quietly succeed, testing nothing.
  defp start_isolated_scheduler do
    test = self()
    room_id = Ecto.UUID.generate()

    owner =
      spawn(fn ->
        {:ok, pid} = GenServer.start(Scheduler, room_id)
        send(test, {:scheduler, pid})

        receive do
          :stop -> Process.exit(pid, :kill)
        end
      end)

    pid =
      receive do
        {:scheduler, pid} -> pid
      after
        2_000 -> flunk("isolated Scheduler did not start")
      end

    on_exit(fn -> send(owner, :stop) end)
    pid
  end

  test "it starts at all when the database is unreachable" do
    # `init/1` used to compute the room's scope inline. A scheduler that cannot
    # start is a scheduler that restart-loops.
    scheduler = start_isolated_scheduler()
    ref = Process.monitor(scheduler)

    refute_receive {:DOWN, ^ref, :process, ^scheduler, _reason}, 500
    assert Process.alive?(scheduler)
  end

  test "a scope change it cannot resolve does not kill it" do
    scheduler = start_isolated_scheduler()
    ref = Process.monitor(scheduler)

    # Resolving this needs the clone's behaviors, and there is no connection.
    send(scheduler, %RoomNPCArrived{
      npc_id: Ecto.UUID.generate(),
      room_id: Ecto.UUID.generate(),
      npc_name: "nobody"
    })

    refute_receive {:DOWN, ^ref, :process, ^scheduler, _reason}, 500
    assert Process.alive?(scheduler)
  end
end
