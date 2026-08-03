defmodule AgenticRealmsWeb.Plugs.RequireServiceToken do
  @moduledoc """
  Feature 018 — guards the NPC service contract routes with the shared bearer
  token. Every request must present `Authorization: Bearer <NPC_SERVICE_SECRET>`;
  a missing, malformed, or incorrect token → `401` with `halt` before any read or
  world change. The comparison is constant-time (`Plug.Crypto.secure_compare/2`),
  and the response never distinguishes a missing token from a wrong one.

  Fail-closed: when the secret is unconfigured (nil/empty), every request is
  rejected.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias AgenticRealms.NpcMinds.Config

  def init(opts), do: opts

  def call(conn, _opts) do
    secret = Config.service_secret()

    with true <- is_binary(secret) and secret != "",
         ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, secret) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
