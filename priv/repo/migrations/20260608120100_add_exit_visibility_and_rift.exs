defmodule AgenticRealms.Repo.Migrations.AddExitVisibilityAndRift do
  use Ecto.Migration

  # Feature 017 — Transient Regions.
  #   * `visible_to_user_id` (nullable) scopes an exit to a single player.
  #     NULL = visible to everyone (the existing global behavior). The
  #     owner-only `:rift` entry exit carries the provision-owner's id here.
  #   * Split the `(source_room_id, direction)` uniqueness into two partial
  #     indexes so an owner-scoped exit can coexist with (and multiple owners
  #     can each own) an exit on the same (source_room_id, direction) slot —
  #     e.g. two players each provisioning a transient region from the same
  #     source room both get a (source, "rift", their-own-id) row.
  #   * Extend the direction CHECK to allow `'rift'` (and, while we're here,
  #     the four feature-012 diagonals, so the constraint matches the
  #     `Direction` module's canonical set).

  def up do
    alter table(:world_exits) do
      add :visible_to_user_id, :bigint
    end

    drop unique_index(:world_exits, [:source_room_id, :direction])

    create unique_index(:world_exits, [:source_room_id, :direction],
             where: "visible_to_user_id IS NULL",
             name: :world_exits_global_uidx
           )

    create unique_index(:world_exits, [:source_room_id, :direction, :visible_to_user_id],
             where: "visible_to_user_id IS NOT NULL",
             name: :world_exits_owned_uidx
           )

    drop constraint(:world_exits, :valid_direction)

    create constraint(:world_exits, :valid_direction,
             check:
               "direction IN ('north','south','east','west','northeast','northwest','southeast','southwest','up','down','rift')"
           )
  end

  def down do
    drop constraint(:world_exits, :valid_direction)

    create constraint(:world_exits, :valid_direction,
             check: "direction IN ('north','south','east','west','up','down')"
           )

    drop unique_index(:world_exits, [:source_room_id, :direction], name: :world_exits_owned_uidx)
    drop unique_index(:world_exits, [:source_room_id, :direction], name: :world_exits_global_uidx)

    create unique_index(:world_exits, [:source_room_id, :direction])

    alter table(:world_exits) do
      remove :visible_to_user_id
    end
  end
end
