defmodule AgenticRealms.World.Examine do
  @moduledoc """
  Resolve a player-supplied target string to a single visible target — an
  object in the room, an object in the player's inventory, a player in
  the same room (including the acting player themselves), or an NPC in
  the same room — and return the data the LiveView needs to render a
  `:detail` log entry.

  Pure read facade. Composes existing reads from `World.Queries`; never
  dispatches commands, never broadcasts.

  The three-stage decision tree (exact > partial; inventory > room;
  mixed-kind tie → refuse) is documented in
  `specs/006-examine-objects/data-model.md` §3 and extended for NPCs in
  `specs/007-static-npcs/data-model.md` §8.

  Parser-injected sentinel `"__self__"` short-circuits scope gathering: the
  acting player is always examinable as themselves regardless of room
  contents. See `contracts/parser.md` for how `look me` / `look self` map.
  NPCs do NOT participate in self-examination grammar — the self-aliases
  resolve only to the acting player.
  """

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Examine.Match
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{NPCClone, PlayerState}
  alias AgenticRealms.World.Stats

  @type error_reason ::
          :no_current_room
          | :no_such_target
          | :ambiguous_in_room
          | :ambiguous_in_inventory
          | :ambiguous_mixed_kind
          | :ambiguous_player
          | :ambiguous_npc
          | :ambiguous_partial

  @type result :: {:ok, Match.t()} | {:error, error_reason()}

  @self_aliases ~w(__self__ me self)

  @doc """
  Resolve `target` for `player_id` to an `Examine.Match` or a refusal reason.

  `target` is expected to have been trimmed and whitespace-collapsed. The
  values `"__self__"` (parser-injected), `"me"`, and `"self"` (LLM-emitted)
  all short-circuit to a self-examination match for the acting player.
  """
  @spec examine(integer(), String.t()) :: result()
  def examine(player_id, target) when is_integer(player_id) and is_binary(target) do
    outcome = do_examine(player_id, target)
    emit_telemetry(player_id, outcome)
    outcome
  end

  defp do_examine(player_id, target) do
    needle = String.downcase(target)

    cond do
      needle in @self_aliases ->
        case acting_username(player_id) do
          {:ok, username} ->
            match = %Match{target_kind: :player, name: username, id: player_id}
            {:ok, enrich(match, player_id, player_level(player_id))}

          :error ->
            {:error, :no_current_room}
        end

      true ->
        case gather_scope(player_id) do
          {:ok, scope} ->
            case resolve(scope, needle) do
              {:ok, match} -> {:ok, enrich(match, scope.examiner_id, scope.examiner_level)}
              {:error, _} = err -> err
            end

          {:error, :no_current_room} = err ->
            err
        end
    end
  end

  # --- Feature 019 — health-tier + relative-power enrichment --------------
  #
  # Enrich the resolved Match with a qualitative health sentence and a
  # relative-power phrase. NEVER exposes exact numbers (FR-020). Self-
  # examination omits the relative-power phrase (FR-021).

  defp enrich(%Match{target_kind: :npc, id: npc_id} = match, _examiner_id, examiner_level) do
    case Repo.get(NPCClone, npc_id) do
      %NPCClone{hp: hp, max_hp: max_hp, level: level}
      when is_integer(hp) and is_integer(max_hp) and is_integer(level) ->
        {_atom, sentence} = Stats.health_tier(hp, max_hp)

        %{
          match
          | health_tier: sentence,
            power_phrase: Stats.relative_power(examiner_level, level)
        }

      _ ->
        match
    end
  end

  defp enrich(%Match{target_kind: :player, id: target_id} = match, examiner_id, examiner_level) do
    case Repo.get(PlayerState, target_id) do
      # Feature 020 — a row with no character has nothing to describe. Mount
      # creates one before anybody can look at anything, so this is the replay
      # window rather than a state a player can reach; falling through leaves
      # the match un-enriched instead of crashing the look.
      %PlayerState{hp: hp, max_hp: max_hp, level: level}
      when is_integer(hp) and is_integer(max_hp) and is_integer(level) ->
        {_atom, sentence} = Stats.health_tier(hp, max_hp)

        power =
          if target_id == examiner_id,
            do: nil,
            else: Stats.relative_power(examiner_level, level)

        %{match | health_tier: sentence, power_phrase: power}

      _ ->
        match
    end
  end

  defp enrich(%Match{} = match, _examiner_id, _examiner_level), do: match

  defp player_level(player_id) do
    case Repo.get(PlayerState, player_id) do
      %PlayerState{level: level} when is_integer(level) -> level
      _ -> 1
    end
  end

  # --- Scope gathering ----------------------------------------------------

  defp gather_scope(player_id) do
    with {:ok, room_id} <- Queries.current_room_of(player_id),
         {:ok, room_view} <- Queries.look_room(player_id) do
      inventory = Queries.list_inventory(player_id)

      players =
        case acting_username(player_id) do
          {:ok, name} -> [%{id: player_id, username: name} | room_view.other_players]
          :error -> room_view.other_players
        end

      {:ok,
       %{
         room_id: room_id,
         room_objects: room_view.objects,
         inventory: inventory,
         players: players,
         npcs: room_view.npcs,
         examiner_id: player_id,
         examiner_level: player_level(player_id)
       }}
    else
      {:error, :no_current_room} -> {:error, :no_current_room}
      {:error, :room_missing} -> {:error, :no_current_room}
    end
  end

  defp acting_username(player_id) do
    case Accounts.get_player(player_id) do
      %{username: u} when is_binary(u) -> {:ok, u}
      _ -> :error
    end
  end

  # --- Stage 1: exact matching --------------------------------------------

  defp resolve(scope, target) do
    exact_room = filter_objects_exact(scope.room_objects, target)
    exact_inv = filter_objects_exact(scope.inventory, target)
    exact_pl = filter_players_exact(scope.players, target)
    exact_npc = filter_npcs_exact(scope.npcs, target)

    total = length(exact_room) + length(exact_inv) + length(exact_pl) + length(exact_npc)

    cond do
      total == 0 ->
        resolve_partial(scope, target)

      total == 1 ->
        from_first_match(exact_room, exact_inv, exact_pl, exact_npc)

      cross_kind_tie?(exact_room, exact_inv, exact_pl, exact_npc) ->
        {:error, :ambiguous_mixed_kind}

      length(exact_pl) > 1 ->
        {:error, :ambiguous_player}

      length(exact_npc) > 1 ->
        {:error, :ambiguous_npc}

      true ->
        resolve_object_tiebreak(exact_room, exact_inv)
    end
  end

  defp cross_kind_tie?(room, inv, pl, npc) do
    has_obj = room != [] or inv != []
    has_pl = pl != []
    has_npc = npc != []
    Enum.count([has_obj, has_pl, has_npc], & &1) > 1
  end

  defp from_first_match([obj], [], [], []), do: {:ok, object_match(obj)}
  defp from_first_match([], [obj], [], []), do: {:ok, object_match(obj)}
  defp from_first_match([], [], [pl], []), do: {:ok, player_match(pl)}
  defp from_first_match([], [], [], [npc]), do: {:ok, npc_match(npc)}

  # --- Stage 2: inventory > room (objects only) ---------------------------

  defp resolve_object_tiebreak([], [_ | _] = inv) when length(inv) > 1,
    do: {:error, :ambiguous_in_inventory}

  defp resolve_object_tiebreak(_room, [single]), do: {:ok, object_match(single)}

  defp resolve_object_tiebreak(_room, []), do: {:error, :ambiguous_in_room}

  defp resolve_object_tiebreak(_room, [_ | _]), do: {:error, :ambiguous_in_inventory}

  # --- Stage 3: partial / substring matching ------------------------------

  defp resolve_partial(scope, target) do
    partial_room = filter_objects_partial(scope.room_objects, target)
    partial_inv = filter_objects_partial(scope.inventory, target)
    partial_pl = filter_players_partial(scope.players, target)
    partial_npc = filter_npcs_partial(scope.npcs, target)

    total =
      length(partial_room) + length(partial_inv) + length(partial_pl) + length(partial_npc)

    case total do
      0 -> {:error, :no_such_target}
      1 -> from_first_match(partial_room, partial_inv, partial_pl, partial_npc)
      _ -> {:error, :ambiguous_partial}
    end
  end

  # --- Filters ------------------------------------------------------------

  defp filter_objects_exact(objs, target),
    do: Enum.filter(objs, fn o -> String.downcase(o.name) == target end)

  defp filter_objects_partial(objs, target),
    do: Enum.filter(objs, fn o -> String.contains?(String.downcase(o.name), target) end)

  defp filter_players_exact(players, target),
    do: Enum.filter(players, fn p -> String.downcase(p.username) == target end)

  defp filter_players_partial(players, target),
    do: Enum.filter(players, fn p -> String.contains?(String.downcase(p.username), target) end)

  defp filter_npcs_exact(npcs, target),
    do: Enum.filter(npcs, fn n -> String.downcase(n.name) == target end)

  defp filter_npcs_partial(npcs, target),
    do: Enum.filter(npcs, fn n -> String.contains?(String.downcase(n.name), target) end)

  # --- Match builders -----------------------------------------------------

  defp object_match(%{name: name} = obj) do
    %Match{target_kind: :object, name: name, long_description: long_description_of(obj)}
  end

  defp player_match(%{id: id, username: name}) do
    %Match{target_kind: :player, name: name, id: id, long_description: nil}
  end

  defp npc_match(%{id: id, name: name}) do
    %Match{
      target_kind: :npc,
      name: name,
      long_description: npc_long_description(id),
      id: id
    }
  end

  # The :objects list from RoomView and the inventory list don't carry
  # long_description (they include only id/name/short_description). Look it
  # up by id from the Object schema directly.
  defp long_description_of(%{id: id}) do
    case AgenticRealms.Repo.get(AgenticRealms.World.Schemas.Object, id) do
      %AgenticRealms.World.Schemas.Object{long_description: ld} -> ld
      _ -> nil
    end
  end

  # NPC clones follow the same pattern — RoomView.npcs omits long_description;
  # look it up by id when we materialize the Match.
  defp npc_long_description(id) do
    case AgenticRealms.Repo.get(AgenticRealms.World.Schemas.NPCClone, id) do
      %AgenticRealms.World.Schemas.NPCClone{long_description: ld} -> ld
      _ -> nil
    end
  end

  # --- Telemetry ----------------------------------------------------------

  defp emit_telemetry(player_id, outcome) do
    {result, target_kind, clone_debug_id} =
      case outcome do
        {:ok, %Match{target_kind: :npc, name: name, id: id}} when not is_nil(id) ->
          {:npc, :npc, "#{name}##{id}"}

        {:ok, %Match{target_kind: kind}} ->
          {kind, kind, nil}

        {:error, reason} ->
          {reason, nil, nil}
      end

    :telemetry.execute(
      [:agenticrealms, :examine, :resolve],
      %{},
      %{
        player_id: player_id,
        outcome: result,
        target_kind: target_kind,
        clone_debug_id: clone_debug_id
      }
    )
  end
end
