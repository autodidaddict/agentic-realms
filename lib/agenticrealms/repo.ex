defmodule AgenticRealms.Repo do
  use Ecto.Repo,
    otp_app: :agenticrealms,
    adapter: Ecto.Adapters.Postgres
end
