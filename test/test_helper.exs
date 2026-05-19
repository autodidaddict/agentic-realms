ExUnit.start(exclude: [:integration, :live_llm])
Ecto.Adapters.SQL.Sandbox.mode(AgenticRealms.Repo, :manual)
