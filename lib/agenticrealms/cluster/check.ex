defmodule AgenticRealms.Cluster.Check do
  @moduledoc """
  Is clustering actually working on this node?

  Every cluster-wide guarantee this app makes rests on a chain, and each link is
  configuration rather than code:

      distribution → discovery → connected peers → Horde membership → one singleton

  The chain degrades **silently**. An unclustered node runs a perfectly healthy
  singleton of its own; `Transient.Manager` reaps and purges, `NpcMinds
  .Reconciler` sweeps, and nothing in a log says the other nodes are doing the
  same thing. `ClusterSingletonTest` proves the Horde wiring in the abstract by
  connecting two nodes itself. This answers the different question — whether a
  *real* deployment has the configuration that would let that happen.

  Run it against a live node. In development:

      mix cluster.check

  In a release, where Mix is not available:

      bin/agenticrealms eval 'AgenticRealms.Cluster.Check.run()'

  `run/0` prints a report and returns `:ok` or `{:error, findings}`. `check/0`
  returns the structured findings without printing, for a health endpoint or a
  deploy gate.
  """

  alias AgenticRealms.NpcMinds
  alias AgenticRealms.World.NPCChat
  alias AgenticRealms.World.Ticks
  alias AgenticRealms.World.Transient

  @typedoc """
  One line of the report. `:ok` is fine, `:warn` is defensible but worth
  knowing, `:error` means a guarantee this app relies on does not hold.
  """
  @type finding :: %{
          section: String.t(),
          label: String.t(),
          status: :ok | :warn | :error,
          detail: String.t()
        }

  # Every Horde registry, and the singleton key each one names, or `nil` where
  # the registry holds per-key processes rather than a singleton.
  @registries [
    {Transient.Registry, :manager, "Transient.Manager", "the region reaper"},
    {NpcMinds.Registry, :reconciler, "NpcMinds.Reconciler", "the mind reconciler"},
    {Ticks.Registry, nil, nil, "per-room tick schedulers"},
    {NPCChat.Registry, nil, nil, "per-(player, NPC) conversations"}
  ]

  # Fixed report order, so the output reads as the chain it is checking.
  @sections ["Distribution", "Discovery", "Peers", "Horde", "Singletons"]

  @doc """
  Run the check and print a report. Returns `:ok`, or `{:error, findings}` when
  something is wrong — so it can gate a deploy by its exit status.
  """
  @spec run() :: :ok | {:error, [finding()]}
  def run do
    findings = check()
    print(findings)

    case Enum.filter(findings, &(&1.status == :error)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  The findings, unprinted.
  """
  @spec check() :: [finding()]
  def check do
    peers = Node.list()

    # Whether clustering was *intended* decides severity. A dev machine that is
    # not distributed is not broken; a node with DNS_CLUSTER_QUERY set that
    # cannot cluster is. A checker that cries wolf on every laptop gets ignored,
    # and then it is not there on the day it matters.
    intent = if query() in [nil, :ignore], do: :single_node, else: :clustered

    distribution(intent) ++ discovery(intent, peers) ++ peers(intent, peers) ++ horde(peers)
  end

  defp query, do: Application.get_env(:agenticrealms, :dns_cluster_query)

  # --- distribution ---------------------------------------------------------

  defp distribution(intent) do
    if Node.alive?() do
      [ok("Distribution", "node", to_string(Node.self())), cookie_finding()]
    else
      [
        finding(
          intent,
          "Distribution",
          "node",
          """
          not distributed — this node has no name, so it can never see a peer. \
          A release needs RELEASE_DISTRIBUTION=name and a routable RELEASE_NODE \
          (the default, sname, is same-host only).\
          """
        )
      ]
    end
  end

  # An error when clustering was intended, a note when it was not.
  defp finding(:clustered, section, label, detail), do: error(section, label, detail)
  defp finding(:single_node, section, label, detail), do: warn(section, label, detail)

  defp cookie_finding do
    case Node.get_cookie() do
      :nocookie -> error("Distribution", "cookie", "not set — peers cannot authenticate")
      _ -> ok("Distribution", "cookie", "set")
    end
  end

  # --- discovery ------------------------------------------------------------

  defp discovery(intent, peers) do
    query = query()

    cond do
      intent == :clustered and peers == [] ->
        [
          error(
            "Discovery",
            "DNS_CLUSTER_QUERY",
            """
            set to #{query}, but no peers are connected. Discovery is configured \
            and finding nothing — check that the query resolves and that the \
            nodes share a cookie.\
            """
          )
        ]

      query in [nil, :ignore] and peers == [] ->
        [
          warn(
            "Discovery",
            "DNS_CLUSTER_QUERY",
            """
            not set, and no peers connected. DNSCluster is inert, so peers will \
            never be found. Correct for a single-node deployment; on more than \
            one node every singleton runs once per node.\
            """
          )
        ]

      query in [nil, :ignore] ->
        [
          warn(
            "Discovery",
            "DNS_CLUSTER_QUERY",
            "not set, but #{length(peers)} peer(s) are connected by some other means"
          )
        ]

      true ->
        [ok("Discovery", "DNS_CLUSTER_QUERY", to_string(query))]
    end
  end

  # --- peers ----------------------------------------------------------------

  defp peers(_intent, []) do
    [
      warn(
        "Peers",
        "connected",
        "none — single-node. Every singleton below is a singleton of one."
      )
    ]
  end

  defp peers(_intent, peers) do
    [ok("Peers", "connected", "#{length(peers)}: #{Enum.map_join(peers, ", ", &to_string/1)}")]
  end

  # --- Horde ----------------------------------------------------------------

  defp horde(peers) do
    expected = length(peers) + 1
    Enum.flat_map(@registries, &registry_findings(&1, expected))
  end

  defp registry_findings({registry, key, singleton_name, description}, expected) do
    name = registry |> Module.split() |> Enum.take(-2) |> Enum.join(".")

    case members(registry) do
      :not_running ->
        [error("Horde", name, "not running — #{description} has no registry")]

      {:ok, members} when length(members) < expected ->
        [
          error(
            "Horde",
            name,
            """
            #{length(members)} member(s), expected #{expected}. Membership has \
            not converged with every connected node, so #{description} is not \
            unique across the cluster.\
            """
          )
        ]

      {:ok, members} ->
        [ok("Horde", name, "#{length(members)} member(s)")] ++
          singleton(registry, key, singleton_name, expected)
    end
  end

  # A registry with a singleton key is the interesting case: it should resolve
  # to one process, and every node should name the same one. Asking the peers
  # is what turns "we configured it" into "it is true right now".
  defp singleton(_registry, nil, _name, _expected), do: []

  defp singleton(registry, key, name, expected) do
    case lookup_everywhere(registry, key) do
      {:error, reason} ->
        [error("Singletons", name, reason)]

      {:ok, []} ->
        [warn("Singletons", name, "not started yet — nothing has needed it")]

      {:ok, [{pid, _node}]} when expected == 1 ->
        [ok("Singletons", name, "running on #{node(pid)} (single-node)")]

      {:ok, pids} ->
        distinct = pids |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

        if length(distinct) == 1 do
          [ok("Singletons", name, "one process on #{node(hd(distinct))}, agreed by every node")]
        else
          [
            error(
              "Singletons",
              name,
              """
              #{length(distinct)} distinct processes across the cluster — nodes \
              disagree about who is running it. For the reaper this means two \
              processes are eligible to hard-delete the same event streams.\
              """
            )
          ]
        end
    end
  end

  # Ask this node and every peer what they resolve the key to. A node that
  # cannot answer is itself the finding.
  defp lookup_everywhere(registry, key) do
    nodes = [Node.self() | Node.list()]

    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case :rpc.call(node, Horde.Registry, :lookup, [registry, key], 5_000) do
        [{pid, _value}] -> {:cont, {:ok, [{pid, node} | acc]}}
        [] -> {:cont, {:ok, acc}}
        {:badrpc, reason} -> {:halt, {:error, "#{node} did not answer: #{inspect(reason)}"}}
      end
    end)
  end

  defp members(registry) do
    if Process.whereis(registry) do
      {:ok, Horde.Cluster.members(registry)}
    else
      :not_running
    end
  rescue
    _ -> :not_running
  end

  # --- reporting ------------------------------------------------------------

  defp ok(section, label, detail),
    do: %{section: section, label: label, status: :ok, detail: detail}

  defp warn(section, label, detail),
    do: %{section: section, label: label, status: :warn, detail: detail}

  defp error(section, label, detail),
    do: %{section: section, label: label, status: :error, detail: detail}

  defp print(findings) do
    IO.puts("\nCluster check — #{Node.self()}\n")

    # Group by section rather than chunking consecutive runs: the Horde and
    # singleton findings are produced per registry and would otherwise alternate.
    by_section = Enum.group_by(findings, & &1.section)

    for section <- @sections, group = by_section[section], group do
      IO.puts("  #{section}")
      Enum.each(group, &IO.puts("    #{mark(&1.status)} #{pad(&1.label)}  #{&1.detail}"))
      IO.puts("")
    end

    IO.puts(summary(findings))
  end

  defp summary(findings) do
    errors = Enum.count(findings, &(&1.status == :error))
    warns = Enum.count(findings, &(&1.status == :warn))

    cond do
      errors > 0 -> "  #{errors} problem(s). A cluster-wide guarantee does not hold.\n"
      warns > 0 -> "  No problems, #{warns} thing(s) worth knowing.\n"
      true -> "  Clustered and converged.\n"
    end
  end

  defp mark(:ok), do: "ok  "
  defp mark(:warn), do: "warn"
  defp mark(:error), do: "FAIL"

  defp pad(label), do: String.pad_trailing(label, 22)
end
