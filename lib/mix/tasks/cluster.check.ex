defmodule Mix.Tasks.Cluster.Check do
  @shortdoc "Report whether clustering is actually working on this node"

  @moduledoc """
  Report whether clustering is actually working on this node.

      mix cluster.check

  Walks the chain every cluster-wide guarantee rests on — distribution,
  discovery, connected peers, Horde membership, one singleton — and says which
  link is broken. Exits non-zero when one is, so it can gate a deploy.

  Mix is not available in a release, so the logic lives in
  `AgenticRealms.Cluster.Check` and this is a wrapper. On a deployed node:

      bin/agenticrealms eval 'AgenticRealms.Cluster.Check.run()'

  Two caveats when running this in development.

  It inspects the node it starts, which is a single unclustered one — a smoke
  test of the configuration, not of a real cluster.

  And `DNS_CLUSTER_QUERY` is read only inside the `:prod` block of
  `config/runtime.exs`, so setting the variable in development changes nothing
  and the report will always say clustering was not intended. That is why the
  severity of "not distributed" is a note here and an error in production.

  To see it find peers, run two named nodes against the same
  `DNS_CLUSTER_QUERY`, or connect them by hand:

      iex --name a@127.0.0.1 --cookie dev -S mix phx.server
      iex --name b@127.0.0.1 --cookie dev -S mix
      # then, in b:  Node.connect(:"a@127.0.0.1"); Mix.Tasks.Cluster.Check.run([])
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    case AgenticRealms.Cluster.Check.run() do
      :ok -> :ok
      {:error, _findings} -> exit({:shutdown, 1})
    end
  end
end
