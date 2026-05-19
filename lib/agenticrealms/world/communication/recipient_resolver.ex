defmodule AgenticRealms.World.Communication.RecipientResolver do
  @moduledoc """
  Resolves a player-typed recipient token to a `%{id, username}` map via
  case-insensitive exact match against `AgenticRealms.Accounts.Player.username`.

  Shared by `World.Communication.tell/3` and `World.Communication.whisper/3`.
  Behavior is governed by FR-010 (case-insensitive exact match, ambiguous
  refusal) and FR-010a (self-target refusal).

  See `specs/004-player-communication/contracts/communication_api.md`.
  """

  import Ecto.Query

  alias AgenticRealms.Accounts.Player
  alias AgenticRealms.Repo

  @type resolved :: %{id: integer(), username: binary()}

  @spec resolve(name :: binary(), sender_id :: integer()) ::
          {:ok, resolved()}
          | {:error, :not_found}
          | {:error, :ambiguous}
          | {:error, :self_target}
  def resolve(name, sender_id) when is_binary(name) and is_integer(sender_id) do
    from(p in Player,
      where: fragment("LOWER(?) = LOWER(?)", p.username, ^name),
      select: %{id: p.id, username: p.username}
    )
    |> Repo.all()
    |> case do
      [] -> {:error, :not_found}
      # Self-target ordering: checked BEFORE ambiguous so a player typing
      # their own name resolves to :self_target even if a case-variant of
      # their name also matches (pathological but possible).
      [%{id: id}] when id == sender_id -> {:error, :self_target}
      [player] -> {:ok, player}
      [_ | _] -> {:error, :ambiguous}
    end
  end
end
