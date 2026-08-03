defmodule AgenticRealms.World.Schemas.Object do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_objects" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :behaviors, {:array, :map}, default: []

    field :container_type, :string
    field :container_id, :string

    belongs_to :quest_player, AgenticRealms.Accounts.Player, foreign_key: :quest_player_id

    belongs_to :quest_instance, AgenticRealms.World.Schemas.QuestInstance,
      type: :binary_id,
      foreign_key: :quest_instance_id

    timestamps(type: :utc_datetime)
  end
end
