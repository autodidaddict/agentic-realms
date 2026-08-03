defmodule AgenticRealms.World.Quest do
  @moduledoc """
  Quest aggregate. One aggregate instance per accepted
  FetchQuest, identified by `quest_id` (binary_id).

  State machine:

      :initial ──AcceptQuest──▶ :active ──FinalizeQuest──▶ :completed

  All state changes emit one event in `:active` direction, and four events
  in `:completed` direction. Refusals return `{:error, atom}` to the
  command-dispatch wrapper, which translates them to the uniform
  `{ok: false, reason: ...}` tool result envelope.

  """

  defstruct quest_id: nil,
            player_id: nil,
            npc_blueprint_id: nil,
            slug: nil,
            state: :initial,
            definition_snapshot: nil,
            accepted_at: nil,
            completed_at: nil

  alias AgenticRealms.World.Commands.{AcceptQuest, FinalizeQuest}

  alias AgenticRealms.World.Events.{
    QuestAccepted,
    QuestItemsConsumed,
    QuestRewardMinted,
    QuestCompleted,
    QuestItemsCleanedUp
  }

  @spec execute(%__MODULE__{}, %AcceptQuest{} | %FinalizeQuest{}) ::
          %QuestAccepted{}
          | [
              %QuestItemsConsumed{}
              | %QuestRewardMinted{}
              | %QuestCompleted{}
              | %QuestItemsCleanedUp{}
            ]
          | {:error, atom()}
  def execute(%__MODULE__{state: :initial}, %AcceptQuest{
        quest_id: qid,
        player_id: pid,
        npc_blueprint_id: bp_id,
        slug: slug,
        definition_snapshot: snapshot,
        accepted_at: at
      }) do
    %QuestAccepted{
      quest_id: qid,
      player_id: pid,
      npc_blueprint_id: bp_id,
      slug: slug,
      definition_snapshot: snapshot,
      accepted_at: at
    }
  end

  def execute(%__MODULE__{state: :active}, %AcceptQuest{}),
    do: {:error, :already_active}

  def execute(%__MODULE__{state: :completed}, _cmd),
    do: {:error, :already_completed}

  def execute(%__MODULE__{state: :initial}, %FinalizeQuest{}),
    do: {:error, :unknown_instance}

  def execute(
        %__MODULE__{state: :active, quest_id: qid, player_id: pid},
        %FinalizeQuest{
          quest_id: qid,
          consumed_object_ids: consumed,
          reward_object_id: reward_oid,
          reward_name: reward_name,
          reward_description: reward_description,
          remaining_quest_object_ids: remaining,
          completed_at: at,
          reward_xp: reward_xp
        }
      ) do
    [
      %QuestItemsConsumed{
        quest_id: qid,
        player_id: pid,
        consumed_object_ids: consumed
      },
      %QuestRewardMinted{
        quest_id: qid,
        player_id: pid,
        reward_object_id: reward_oid,
        reward_name: reward_name,
        reward_description: reward_description
      },
      %QuestCompleted{
        quest_id: qid,
        player_id: pid,
        completed_at: at,
        xp: reward_xp
      },
      %QuestItemsCleanedUp{
        quest_id: qid,
        remaining_quest_object_ids: remaining
      }
    ]
  end

  @spec apply(
          %__MODULE__{},
          %QuestAccepted{}
          | %QuestCompleted{}
          | %QuestItemsConsumed{}
          | %QuestRewardMinted{}
          | %QuestItemsCleanedUp{}
        ) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %QuestAccepted{
        quest_id: qid,
        player_id: pid,
        npc_blueprint_id: bp_id,
        slug: slug,
        definition_snapshot: snapshot,
        accepted_at: at
      }) do
    %__MODULE__{
      state
      | quest_id: qid,
        player_id: pid,
        npc_blueprint_id: bp_id,
        slug: slug,
        state: :active,
        definition_snapshot: snapshot,
        accepted_at: at,
        completed_at: nil
    }
  end

  def apply(%__MODULE__{} = state, %QuestCompleted{completed_at: at}) do
    %__MODULE__{state | state: :completed, completed_at: at}
  end

  def apply(%__MODULE__{} = state, %QuestItemsConsumed{}), do: state
  def apply(%__MODULE__{} = state, %QuestRewardMinted{}), do: state
  def apply(%__MODULE__{} = state, %QuestItemsCleanedUp{}), do: state
end
