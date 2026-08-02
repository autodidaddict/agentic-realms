defmodule AgenticRealms.ClusterPeer do
  @moduledoc """
  Peer-node setup for `AgenticRealms.World.ClusterSingletonTest`.

  Lives in `test/support` rather than beside the test because it has to run on
  the *other* node. `elixirc_paths(:test)` compiles this directory into the
  app's ebin, so `:code.add_paths/1` puts it on the peer's code path; a module
  defined in a test file is compiled in memory and would not be there.

  Starts PubSub and every Horde registry/supervisor pair. No Repo and no
  endpoint: the singletons touch the database only on their sweep timers, which
  are far longer than any test, and a second endpoint would fight for the port.
  """

  alias AgenticRealms.NpcMinds
  alias AgenticRealms.World.NPCChat
  alias AgenticRealms.World.Ticks
  alias AgenticRealms.World.Transient

  @sup __MODULE__.Supervisor

  @doc """
  Start the singleton's dependencies on this node. Idempotent, so the test can
  call it on both nodes without special-casing which one it is on.
  """
  @spec start() :: {:ok, :started}
  def start do
    {:ok, _} = Application.ensure_all_started(:horde)
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

    unless Process.whereis(@sup) do
      # All four Horde pairs, not just the one under test: `Cluster.Check`
      # inspects every registry, and a peer missing one would look like a real
      # finding. They are cheap — a registry and a dynamic supervisor each, no
      # database.
      #
      # The primary already runs some of these as application children and the
      # peer runs none, so filter to what is actually missing. One helper, both
      # nodes, no special-casing which one we are on.
      children =
        [
          {Phoenix.PubSub, name: AgenticRealms.PubSub},
          Transient.Registry,
          Transient.Supervisor,
          NpcMinds.Registry,
          NpcMinds.Supervisor,
          Ticks.Registry,
          Ticks.Supervisor,
          NPCChat.Registry,
          NPCChat.Supervisor
        ]
        |> Enum.reject(&running?/1)

      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one, name: @sup)

      # `Supervisor.start_link/2` links to the caller, and on the peer the
      # caller is the short-lived process handling `:peer.call/4`. Without this
      # the whole tree dies the moment the call returns, and the only symptom is
      # a missing ETS table several assertions later. The peer node is torn down
      # wholesale by `:peer.stop/1`, so an unlinked supervisor leaks nothing.
      Process.unlink(pid)
    end

    {:ok, :started}
  end

  defp running?({Phoenix.PubSub, name: name}), do: !!Process.whereis(name)
  defp running?(module) when is_atom(module), do: !!Process.whereis(module)
end
