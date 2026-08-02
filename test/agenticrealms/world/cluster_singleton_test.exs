defmodule AgenticRealms.World.ClusterSingletonTest do
  @moduledoc """
  Two real BEAM nodes, one singleton.

  Every cluster-wide guarantee this app makes rests on a chain: the node is
  distributed, peers are discovered and connected, `Horde.Registry` sees them as
  members, and a `:via` name therefore resolves to one process. Each link is
  configuration, and the whole thing degrades **silently** — an unclustered node
  runs a perfectly healthy singleton of its own, and nothing looks wrong.

  That matters most for `Transient.Manager`, whose reaper hard-deletes
  event-store streams. Two of them sweeping is not a duplicated log line; it is
  two processes purging the same rows. So this starts an actual second node and
  asserts the property end to end, rather than asserting that we passed
  `members: :auto` somewhere.

  ## Running it

  Excluded by default: it needs EPMD, starts a peer node, and waits on a CRDT.

      epmd -daemon
      mix test --include cluster test/agenticrealms/world/cluster_singleton_test.exs

  Without EPMD, `:net_kernel.start/1` fails with `:nodistribution` — worth
  knowing, because it is the same prerequisite a real deployment has, and the
  same silence when it is missing.

  ## What this proves, and what it does not

  It proves the Horde wiring: given two connected nodes, exactly one manager
  exists and both resolve to it. It connects them with `Node.connect/1`, so it
  does **not** exercise `DNSCluster` or `DNS_CLUSTER_QUERY` — discovery is
  deployment configuration this test cannot see, and today nothing sets that
  variable.

  Failover is also not asserted. Horde does relocate the manager when its node
  leaves, but observing it means disconnecting the peer mid-suite, which leaves
  the remaining tests running against a half-torn-down cluster. A flaky test
  about failover would be worth less than an honest note that it is untested.
  """
  use ExUnit.Case, async: false

  @moduletag :cluster
  # Starting a peer node, seeding its code path, and letting Horde's membership
  # CRDT converge is slow by nature.
  @moduletag timeout: 120_000

  alias AgenticRealms.ClusterPeer
  alias AgenticRealms.World.Transient

  setup_all do
    # `mix test` is not distributed. Membership is a property of connected
    # nodes, so there is nothing to observe until this node has a name.
    unless Node.alive?() do
      case :net_kernel.start([:"primary@127.0.0.1", :longnames]) do
        {:ok, _} ->
          Node.set_cookie(:cluster_smoke_test)

        {:error, _} ->
          raise """
          Could not start distribution. EPMD is almost certainly not running:

              epmd -daemon

          This is the same prerequisite a clustered deployment has.
          """
      end
    end

    # `connection: :standard_io` gives a control channel independent of BEAM
    # distribution, so `:peer.call/4` reaches the peer regardless of whether the
    # nodes are connected — including while we are still setting them up.
    {:ok, peer, node} =
      :peer.start_link(%{
        name: :secondary,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", ~c"cluster_smoke_test"]
      })

    # The peer starts empty: hand it this project's compiled code and the same
    # application environment, then start what the singleton needs on both.
    :peer.call(peer, :code, :add_paths, [:code.get_path()])

    for {key, value} <- Application.get_all_env(:agenticrealms) do
      :peer.call(peer, Application, :put_env, [:agenticrealms, key, value])
    end

    {:ok, :started} = :peer.call(peer, ClusterPeer, :start, [])
    {:ok, :started} = ClusterPeer.start()

    true = Node.connect(node)
    await(fn -> length(Horde.Cluster.members(Transient.Registry)) == 2 end)

    # `start_link` above already ties the peer's lifetime to this setup_all
    # process, which ExUnit kills once the module's tests finish. So there are
    # two things trying to stop the node, and they race: this is the tidy path
    # when it wins, and when the link wins instead `:peer.stop/1` exits —
    # `normal` if it catches the process mid-shutdown, `noproc` once it is
    # fully gone. An uncaught exit here fails setup_all and invalidates four
    # tests that already passed, which is how CI reported it. The node is gone
    # either way, so the exit is noise.
    on_exit(fn ->
      try do
        :peer.stop(peer)
      catch
        :exit, _ -> :ok
      end
    end)

    %{peer: peer, node: node}
  end

  test "both nodes are members of one registry", %{node: node} do
    assert node in Node.list()

    members = Horde.Cluster.members(Transient.Registry)

    assert length(members) == 2
    assert Enum.sort(Enum.map(members, &elem(&1, 1))) == Enum.sort([Node.self(), node])
  end

  test "exactly one manager exists, and both nodes resolve to it", %{peer: peer} do
    # Ask both nodes to ensure it. Were the cluster not converged, each would
    # happily start its own — precisely the failure this guards against.
    {:ok, here} = Transient.Supervisor.ensure_manager()
    {:ok, there} = :peer.call(peer, Transient.Supervisor, :ensure_manager, [])

    assert here == there,
           """
           Two managers. The reaper hard-deletes event-store streams, so this \
           means two processes are eligible to purge the same regions.
           """

    # And a plain lookup from either side agrees, which is the path every
    # caller goes through.
    await(fn -> :peer.call(peer, Transient.Registry, :lookup, []) == {:ok, here} end)

    assert Transient.Registry.lookup() == {:ok, here}
    assert :peer.call(peer, Transient.Registry, :lookup, []) == {:ok, here}
  end

  test "the manager is alive on exactly one of the two nodes", %{peer: peer} do
    {:ok, pid} = Transient.Supervisor.ensure_manager()
    peer_node = :peer.call(peer, Node, :self, [])

    assert node(pid) in [Node.self(), peer_node]

    alive? =
      if node(pid) == Node.self(),
        do: Process.alive?(pid),
        else: :peer.call(peer, Process, :alive?, [pid])

    assert alive?
  end

  describe "mix cluster.check" do
    test "reports a converged cluster with no problems", %{node: node} do
      # The checker is the only thing that will ever look at a real deployment,
      # so it gets exercised against a real cluster here rather than trusted.
      # Make sure the singleton exists regardless of which order the tests ran.
      {:ok, _} = Transient.Supervisor.ensure_manager()

      findings = AgenticRealms.Cluster.Check.check()

      refute Enum.any?(findings, &(&1.status == :error)),
             "unexpected problems: #{inspect(Enum.filter(findings, &(&1.status == :error)))}"

      peers = Enum.find(findings, &(&1.section == "Peers"))
      assert peers.status == :ok
      assert peers.detail =~ to_string(node)

      # Every Horde registry should see both nodes.
      for f <- Enum.filter(findings, &(&1.section == "Horde")) do
        assert f.status == :ok, "#{f.label}: #{f.detail}"
        assert f.detail =~ "2 member(s)"
      end

      # And the reaper resolves to one process that every node agrees on.
      reaper = Enum.find(findings, &(&1.label == "Transient.Manager"))
      assert reaper.status == :ok
      assert reaper.detail =~ "agreed by every node"
    end
  end

  # Horde converges rather than replies, so membership assertions are
  # eventually-true. Polling beats a fixed sleep: fast when it converges fast,
  # and it fails with a clear message when it does not.
  defp await(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts > 0 -> Process.sleep(100) && await(fun, attempts - 1)
      true -> flunk("cluster did not converge within 10s")
    end
  end
end
