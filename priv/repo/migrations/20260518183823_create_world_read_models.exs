defmodule AgenticRealms.Repo.Migrations.CreateWorldReadModels do
  use Ecto.Migration

  def change do
    create table(:world_rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:world_exits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :source_room_id,
          references(:world_rooms, type: :binary_id, on_delete: :delete_all),
          null: false

      add :direction, :string, null: false

      add :target_room_id,
          references(:world_rooms, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:world_exits, [:source_room_id, :direction])

    create constraint(:world_exits, :valid_direction,
             check: "direction IN ('north','south','east','west','up','down')"
           )

    create table(:world_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false
      add :fixed, :boolean, null: false, default: false
      add :room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)
      add :player_id, references(:players, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:world_objects, [:room_id])
    create index(:world_objects, [:player_id])
    create index(:world_objects, ["LOWER(name)"], name: :world_objects_lower_name_index)

    create constraint(:world_objects, :exactly_one_location,
             check: "(room_id IS NOT NULL) <> (player_id IS NOT NULL)"
           )

    create table(:player_state, primary_key: false) do
      add :player_id, references(:players, on_delete: :delete_all), primary_key: true
      add :current_room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)

      timestamps(type: :utc_datetime)
    end

    create index(:player_state, [:current_room_id])
  end
end
