ExUnit.start(exclude: [:integration, :live_llm, :cluster])
Ecto.Adapters.SQL.Sandbox.mode(AgenticRealms.Repo, :manual)
