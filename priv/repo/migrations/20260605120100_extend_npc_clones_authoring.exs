defmodule AgenticRealms.Repo.Migrations.ExtendNpcClonesAuthoring do
  use Ecto.Migration

  @moduledoc """
  Feature 015 — NPC clone authoring provenance. `fixed` (parity), `behavior_groups`
  (frozen behavior_group names referenced at spawn) and `direct_behaviors` (frozen
  non-behavior_group behaviors) let extract-essence reconstruct a blueprint draft
  faithfully; the existing `behaviors` column stays the effective union.
  """

  def change do
    alter table(:npc_clones) do
      add :fixed, :boolean, null: false, default: false
      add :behavior_groups, {:array, :string}, null: false, default: []
      add :direct_behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
