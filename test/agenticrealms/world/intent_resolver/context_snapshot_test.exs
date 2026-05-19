defmodule AgenticRealms.World.IntentResolver.ContextSnapshotTest do
  @moduledoc """
  Unit tests for the volatile user-message rendering. Exercises `render/3`
  directly with fixture data — no database required.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.IntentResolver.ContextSnapshot

  defp room(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Stone Atrium",
        description: "A wide, pillared hall of mossy granite.",
        exits: [
          %{direction: "north", target_name: "Forest Path"},
          %{direction: "east", target_name: "Corridor"}
        ],
        objects: [%{name: "brass lantern"}, %{name: "leather-bound journal"}],
        other_players: [%{username: "bob"}]
      },
      overrides
    )
  end

  test "renders room name, description, exits, objects, occupants, inventory, and input" do
    text = ContextSnapshot.render(room(), [%{name: "iron key"}], "grab the lantern")

    assert text =~ "Current room: Stone Atrium"
    assert text =~ "A wide, pillared hall of mossy granite."
    assert text =~ "north (Forest Path)"
    assert text =~ "east (Corridor)"
    assert text =~ "Objects here: brass lantern, leather-bound journal"
    assert text =~ "Other players present: bob"
    assert text =~ "Your inventory: iron key"
    assert text =~ "Player typed: grab the lantern"
  end

  test "preserves the player's literal input — casing and internal whitespace" do
    text = ContextSnapshot.render(room(), [], "GRAB  the   Lantern")
    assert text =~ "Player typed: GRAB  the   Lantern"
  end

  test "empty collections render as explicit placeholders" do
    bare = room(%{exits: [], objects: [], other_players: []})
    text = ContextSnapshot.render(bare, [], "look")

    assert text =~ "Exits: (none)"
    assert text =~ "Objects here: (none)"
    assert text =~ "Other players present: (none)"
    assert text =~ "Your inventory: (empty)"
  end

  test "truncates a long room description to 300 characters with an ellipsis" do
    long = String.duplicate("x", 500)
    text = ContextSnapshot.render(room(%{description: long}), [], "look")

    # The description line carries 300 chars + "…"; assert the ellipsis is
    # present and the full 500-char string is not.
    refute text =~ String.duplicate("x", 500)
    assert text =~ "…"
    assert text =~ String.duplicate("x", 300)
  end

  test "a description at exactly the limit is not truncated" do
    exact = String.duplicate("y", 300)
    text = ContextSnapshot.render(room(%{description: exact}), [], "look")

    assert text =~ exact
    refute text =~ "…"
  end
end
