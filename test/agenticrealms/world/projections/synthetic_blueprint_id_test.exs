defmodule AgenticRealms.World.Projections.SyntheticBlueprintIdTest do
  @moduledoc """
  Unit tests for `SyntheticBlueprintId.derive/3` — the deterministic id
  generator used by the projector's legacy `NPCSpawnedInRoom` replay path
  (feature 008 FR-019 / FR-020 / FR-021).
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Projections.SyntheticBlueprintId

  describe "derive/3" do
    test "same payload always produces the same id (determinism)" do
      id1 =
        SyntheticBlueprintId.derive(
          "Garrick the Innkeeper",
          "a wiry innkeeper",
          "A wiry man in a stained apron."
        )

      id2 =
        SyntheticBlueprintId.derive(
          "Garrick the Innkeeper",
          "a wiry innkeeper",
          "A wiry man in a stained apron."
        )

      assert id1 == id2
    end

    test "different name produces a different id" do
      id1 =
        SyntheticBlueprintId.derive(
          "Garrick the Innkeeper",
          "a wiry innkeeper",
          "A wiry man in a stained apron."
        )

      id2 =
        SyntheticBlueprintId.derive(
          "Maelyn the Bard",
          "a wiry innkeeper",
          "A wiry man in a stained apron."
        )

      refute id1 == id2
    end

    test "different short_description produces a different id" do
      id1 = SyntheticBlueprintId.derive("X", "short A", "long")
      id2 = SyntheticBlueprintId.derive("X", "short B", "long")

      refute id1 == id2
    end

    test "different long_description produces a different id" do
      id1 = SyntheticBlueprintId.derive("X", "short", "long A")
      id2 = SyntheticBlueprintId.derive("X", "short", "long B")

      refute id1 == id2
    end

    test "ids are prefixed with 'synthetic-' for visual distinction from authored slugs" do
      id = SyntheticBlueprintId.derive("X", "short", "long")
      assert String.starts_with?(id, "synthetic-")
    end

    test "ids are lowercase hex digests (no uppercase, no special characters beyond '-')" do
      id = SyntheticBlueprintId.derive("Some NPC", "short", "long")
      assert Regex.match?(~r/\Asynthetic-[a-f0-9]{64}\z/, id)
    end
  end
end
