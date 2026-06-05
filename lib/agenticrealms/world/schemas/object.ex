defmodule AgenticRealms.World.Schemas.Object do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_objects" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :behaviors, {:array, :map}, default: []

    # Feature 016 — typed containment. `container_type` is one of
    # "void" | "room" | "player" | "npc"; `container_id` holds the room
    # UUID, the stringified player id, or NULL for the void. Replaces the
    # old `room_id`/`player_id` + XOR model.
    field :container_type, :string
    field :container_id, :string

    # Feature 013 — Quests. Both NULL for non-quest items; both set
    # together for quest-scoped items spawned via accept_quest.
    # DB check constraint enforces the pairing.
    belongs_to :quest_player, AgenticRealms.Accounts.Player, foreign_key: :quest_player_id

    belongs_to :quest_instance, AgenticRealms.World.Schemas.QuestInstance,
      type: :binary_id,
      foreign_key: :quest_instance_id

    timestamps(type: :utc_datetime)
  end
end
