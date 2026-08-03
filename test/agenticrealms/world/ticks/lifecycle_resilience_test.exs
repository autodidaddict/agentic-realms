defmodule AgenticRealms.World.Ticks.LifecycleResilienceTest do
  @moduledoc """
  `Ticks.Lifecycle` must survive a database it cannot reach.

  It is always-on, it queries on both startup and presence changes, and it was
  a sibling of the Repo under a `:one_for_one` supervisor. Crashing on a query
  therefore did not cost one update: the restart re-ran the same query, and
  exceeding `max_restarts` terminates every sibling, Repo included. A nightly
  seed run caught that as 342 tests failing with "could not lookup Ecto repo"
  after a single torn-down connection.

  Everything here runs against a private, unregistered instance. The
  registered singleton is shared by the whole suite, and an earlier version of
  this file drove it directly — which tipped an unrelated LiveView test into
  failing about a third of the time. Nothing below touches global state.

  `async: true` is load-bearing: async tests own their sandbox connection
  rather than sharing it, which is what lets us start a Lifecycle that has no
  connection to borrow. That is the failure being tested, and it is the same
  situation `QueriesPlayersInRoomTest` documents avoiding rather than
  provoking.
  """

  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.World.Ticks.Lifecycle

  # A Lifecycle with no route to a connection.
  #
  # It is started from a bare `spawn/1`, which sets neither `$callers` nor
  # `$ancestors` back to this test process — so the sandbox has no owner to
  # resolve and every query fails. Starting it from the test process directly
  # would inherit ownership through `$callers` and quietly succeed, testing
  # nothing.
  defp start_isolated_lifecycle do
    test = self()

    owner =
      spawn(fn ->
        {:ok, pid} = GenServer.start(Lifecycle, [])
        send(test, {:lifecycle, pid})

        receive do
          :stop -> Process.exit(pid, :kill)
        end
      end)

    pid =
      receive do
        {:lifecycle, pid} -> pid
      after
        2_000 -> flunk("isolated Lifecycle did not start")
      end

    on_exit(fn -> send(owner, :stop) end)
    pid
  end

  test "a presence diff it cannot resolve against the database does not kill it" do
    lifecycle = start_isolated_lifecycle()
    ref = Process.monitor(lifecycle)

    # Resolving this join needs `Queries.current_room_of/1`, and there is no
    # connection to be had.
    send(lifecycle, %{
      event: "presence_diff",
      payload: %{joins: %{"987654321" => %{}}, leaves: %{}}
    })

    refute_receive {:DOWN, ^ref, :process, ^lifecycle, _reason}, 500
    assert Process.alive?(lifecycle)
  end

  test "it starts at all when the database is unreachable" do
    # The startup rebuild reads the database. If that runs inline in `init/1`,
    # an unavailable database means the process cannot start — and a process
    # that cannot start is a process that restart-loops. Deferring the rebuild
    # to `handle_continue/2` keeps it (it still runs before any other message)
    # while letting a failed attempt retry instead of crash.
    lifecycle = start_isolated_lifecycle()
    ref = Process.monitor(lifecycle)

    refute_receive {:DOWN, ^ref, :process, ^lifecycle, _reason}, 500
    assert Process.alive?(lifecycle)
  end
end
