defmodule AgenticRealms.World.PlayerNames do
  @moduledoc """
  What a player is called, and the one place the world asks.

  Since interactive character creation, the character name is a player's
  identity everywhere another player can see them: room occupant lists, speech,
  emotes, whispers, and presence. The account username went back to being a
  login credential, so nothing under `AgenticRealms.World` or
  `AgenticRealmsWeb` reads it except the authentication path.

  Reads the projected `player_state` row. A `nil` from `get/1` means "this
  player has no character yet", which is what `GameLive`'s mount branches on to
  decide between the creation dialog and the world.

  Stateless, so there is nothing to supervise and nothing that differs per node.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.PlayerState

  @doc """
  A player's character name, or `nil` when they have not created one.
  """
  @spec get(integer()) :: String.t() | nil
  def get(player_id) when is_integer(player_id) do
    Repo.one(
      from(ps in PlayerState,
        where: ps.player_id == ^player_id,
        select: ps.character_name
      )
    )
  end

  @doc """
  The names of several players at once, keyed by player id.

  Players with no character are absent from the map rather than mapped to `nil`,
  so a caller can tell "not created" from "created and somehow blank" without a
  second check.
  """
  @spec get_many([integer()]) :: %{integer() => String.t()}
  def get_many([]), do: %{}

  def get_many(player_ids) when is_list(player_ids) do
    Repo.all(
      from(ps in PlayerState,
        where: ps.player_id in ^player_ids and not is_nil(ps.character_name),
        select: {ps.player_id, ps.character_name}
      )
    )
    |> Map.new()
  end

  @doc """
  The player holding a character name, compared without regard to case, or
  `nil` when nobody holds it.

  Uses the `lower(character_name)` index. A blank name matches nothing rather
  than matching a row whose character has not been created.
  """
  @spec find_by_name(String.t()) :: integer() | nil
  def find_by_name(name) when is_binary(name) do
    case normalize(name) do
      "" ->
        nil

      normalized ->
        Repo.one(
          from(ps in PlayerState,
            where: fragment("lower(?)", ps.character_name) == ^normalized,
            select: ps.player_id,
            limit: 1
          )
        )
    end
  end

  @doc """
  Whether a character name is already held.

  A courtesy for the creation dialog, not an authority. The `CharacterName`
  aggregate decides at confirmation, and a name shown as available here can be
  claimed by somebody else before the player finishes.
  """
  @spec taken?(String.t()) :: boolean()
  def taken?(name) when is_binary(name), do: find_by_name(name) != nil

  @doc """
  The form of a name used to compare two of them: trimmed and downcased.

  The aggregate's stream is keyed by this, so it lives here rather than being
  spelled out at each call site.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(name) when is_binary(name), do: name |> String.trim() |> String.downcase()
end
