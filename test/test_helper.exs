# `:cluster` starts BEAM distribution and a peer node. That is global state —
# it leaks into every other test in the run — so it is opt-in, like the tags
# above. See AgenticRealms.World.ClusterSingletonTest.
ExUnit.start(exclude: [:integration, :live_llm, :cluster])
Ecto.Adapters.SQL.Sandbox.mode(AgenticRealms.Repo, :manual)
