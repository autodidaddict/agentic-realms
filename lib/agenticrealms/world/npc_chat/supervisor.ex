defmodule AgenticRealms.World.NPCChat.Supervisor do
  @moduledoc """
  Cluster-wide dynamic supervisor for `NPCChat.Conversation` processes.
  Wraps `Horde.DynamicSupervisor` so a Conversation may
  be started on any node in the cluster; Horde decides placement via
  `Horde.UniformDistribution`.

  Idle conversations terminate themselves with `{:stop, :normal, _}`
  (see `Conversation` module's idle-timeout handler); Horde reaps the
  registry entry automatically.
  """

  alias AgenticRealms.World.NPCChat.{Conversation, Registry}

  @doc false
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start:
        {Horde.DynamicSupervisor, :start_link,
         [
           [
             name: __MODULE__,
             strategy: :one_for_one,
             members: :auto,
             distribution_strategy: Horde.UniformDistribution
           ]
         ]},
      type: :supervisor
    }
  end

  @doc """
  Find an existing Conversation pid for `{player_id, npc_clone}` or start
  one if none is registered. Returns `{:ok, pid}` either way.

  The clone struct is passed (not just its id) so the new Conversation
  can cache `npc_name` and `lore` at init time without a Repo round-trip.
  """
  @spec find_or_start(integer(), %AgenticRealms.World.Schemas.NPCClone{}) ::
          {:ok, pid()} | {:error, term()}
  def find_or_start(player_id, %{id: clone_id} = clone) when is_integer(player_id) do
    key = {player_id, clone_id}

    case Registry.lookup(key) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        spec = %{
          id: Conversation,
          start: {Conversation, :start_link, [{player_id, clone}]},
          restart: :transient,
          shutdown: 5_000
        }

        case Horde.DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          other ->
            other
        end
    end
  end
end
