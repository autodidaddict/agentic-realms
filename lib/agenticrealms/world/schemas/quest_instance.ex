defmodule AgenticRealms.World.Schemas.QuestInstance do
  @moduledoc """
  Ecto schema for `quest_instances`. One row per accepted FetchQuest
  instance.

  `definition_snapshot` is the full quest definition (instance-scoped quest
  tags already substituted) captured at accept time. Reads against this
  schema should treat `definition_snapshot`'s nested keys as atoms — the
  eventstore JsonSerializer atomizes JSON keys at deserialize time, and
  every read path goes through projected state populated via that
  deserialization. See `specs/013-quest-system/data-model.md` § 2.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "quest_instances" do
    field :slug, :string
    field :state, :string
    field :accepted_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :definition_snapshot, :map
    field :reward_object_id, :binary_id

    belongs_to :player, AgenticRealms.Accounts.Player
    belongs_to :npc_blueprint, AgenticRealms.World.Schemas.NPCBlueprint, type: :string

    has_many :scoped_objects, AgenticRealms.World.Schemas.Object, foreign_key: :quest_instance_id

    timestamps(type: :utc_datetime)
  end
end
