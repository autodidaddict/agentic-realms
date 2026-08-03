defmodule AgenticRealms.World.Ticks.Subsystem do
  @moduledoc """
  Groups the room-tick processes under one supervisor.

  These three were siblings of the Repo and the Endpoint under
  `AgenticRealms.Supervisor`. That strategy is `:one_for_one`, which restarts
  only the child that died — but exceeding `max_restarts` terminates the
  supervisor and therefore *every* child, whichever one was flapping. So a
  `Lifecycle` that crash-looped took the Repo down with it, and everything
  afterwards failed with "could not lookup Ecto repo".

  A level of supervision in between means the churn is absorbed here. It does
  not make the top level unreachable — a crash loop persistent enough to
  collapse this supervisor repeatedly still propagates — but it raises the bar
  from three crashes to roughly an order of magnitude more, and it keeps a
  restarting tick scheduler from counting against the Repo's budget.

  The real fix for the case we hit is in `Lifecycle`, which no longer dies when
  a query fails. This is the second line.

  Registered names are unchanged, so `Cluster.Check` and the two-node test
  still find `Ticks.Registry` and `Ticks.Supervisor` where they expect them.
  """

  use Supervisor

  alias AgenticRealms.World.Ticks

  @doc false
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Ticks.Registry,
      Ticks.Supervisor,
      Ticks.Lifecycle
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
