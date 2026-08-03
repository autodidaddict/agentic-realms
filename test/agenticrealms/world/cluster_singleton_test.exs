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
  @moduletag timeout: 120_000

  alias AgenticRealms.ClusterPeer
  alias AgenticRealms.World.Transient

  setup_all do
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

    {:ok, peer, node} =
      :peer.start_link(%{
        name: :secondary,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", ~c"cluster_smoke_test"]
      })

    :peer.call(peer, :code, :add_paths, [:code.get_path()])

    for {key, value} <- Application.get_all_env(:agenticrealms) do
      :peer.call(peer, Application, :put_env, [:agenticrealms, key, value])
    end

    {:ok, :started} = :peer.call(peer, ClusterPeer, :start, [])
    {:ok, :started} = ClusterPeer.start()

    true = Node.connect(node)
    await(fn -> length(Horde.Cluster.members(Transient.Registry)) == 2 end)

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
    {:ok, here} = Transient.Supervisor.ensure_manager()
    {:ok, there} = :peer.call(peer, Transient.Supervisor, :ensure_manager, [])

    assert here == there,
           """
           Two managers. The reaper hard-deletes event-store streams, so this \
           means two processes are eligible to purge the same regions.
           """

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
      {:ok, _} = Transient.Supervisor.ensure_manager()

      findings = AgenticRealms.Cluster.Check.check()

      refute Enum.any?(findings, &(&1.status == :error)),
             "unexpected problems: #{inspect(Enum.filter(findings, &(&1.status == :error)))}"

      peers = Enum.find(findings, &(&1.section == "Peers"))
      assert peers.status == :ok
      assert peers.detail =~ to_string(node)

      for f <- Enum.filter(findings, &(&1.section == "Horde")) do
        assert f.status == :ok, "#{f.label}: #{f.detail}"
        assert f.detail =~ "2 member(s)"
      end

      reaper = Enum.find(findings, &(&1.label == "Transient.Manager"))
      assert reaper.status == :ok
      assert reaper.detail =~ "agreed by every node"
    end
  end

  defp await(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts > 0 -> Process.sleep(100) && await(fun, attempts - 1)
      true -> flunk("cluster did not converge within 10s")
    end
  end
end
