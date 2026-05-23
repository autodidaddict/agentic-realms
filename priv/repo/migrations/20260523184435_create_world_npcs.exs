defmodule AgenticRealms.Repo.Migrations.CreateWorldNpcs do
  use Ecto.Migration

  def change do
    create table(:world_npcs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false

      add :room_id,
          references(:world_rooms, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:world_npcs, [:room_id])

    create unique_index(
             :world_npcs,
             ["room_id", "LOWER(name)"],
             name: :world_npcs_room_id_lower_name_index
           )
  end
end
