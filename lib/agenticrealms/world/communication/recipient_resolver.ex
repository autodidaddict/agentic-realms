defmodule AgenticRealms.World.Communication.RecipientResolver do
  @moduledoc """
  Resolves a player-typed recipient token to a `%{id, name}` map via
  case-insensitive exact match against a character's name.

  Players are addressed by their character's name, not their
  login. A player with no character has no name to be addressed by, and is never
  in a room to be whispered at.

  Shared by `World.Communication.tell/3` and `World.Communication.whisper/3`.
  Matching is case-insensitive and exact; an ambiguous name is refused, as
  is targeting yourself.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.PlayerState

  @type resolved :: %{id: integer(), name: binary()}

  @spec resolve(name :: binary(), sender_id :: integer()) ::
          {:ok, resolved()}
          | {:error, :not_found}
          | {:error, :ambiguous}
          | {:error, :self_target}
  def resolve(name, sender_id) when is_binary(name) and is_integer(sender_id) do
    from(ps in PlayerState,
      where: fragment("LOWER(?) = LOWER(?)", ps.character_name, ^name),
      select: %{id: ps.player_id, name: ps.character_name}
    )
    |> Repo.all()
    |> case do
      [] -> {:error, :not_found}
      [%{id: id}] when id == sender_id -> {:error, :self_target}
      [player] -> {:ok, player}
      [_ | _] -> {:error, :ambiguous}
    end
  end
end
