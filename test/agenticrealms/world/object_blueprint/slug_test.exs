defmodule AgenticRealms.World.ObjectBlueprint.SlugTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.ObjectBlueprint.Slug

  describe "derive/1" do
    test "lowercases and underscore-joins multi-word names" do
      assert Slug.derive("Brass-Bound Chest") == "brass_bound_chest"
    end

    test "collapses runs of punctuation/whitespace to a single underscore" do
      assert Slug.derive("brass  --  bound...chest") == "brass_bound_chest"
    end

    test "trims leading and trailing underscores" do
      assert Slug.derive("  !chest!  ") == "chest"
    end

    test "prepends `b_` when the candidate would start with a digit" do
      assert Slug.derive("7 iron chest") == "b_7_iron_chest"
    end

    test "truncates to the 64-character upper bound" do
      long = String.duplicate("a", 100)
      derived = Slug.derive(long)
      assert String.length(derived) == 64
    end

    test "rejects pure-punctuation names by yielding empty string" do
      assert Slug.derive("!!! ??? ...") == ""
    end
  end

  describe "valid?/1" do
    test "accepts a clean slug" do
      assert Slug.valid?("brass_bound_chest")
    end

    test "rejects empty string" do
      refute Slug.valid?("")
    end

    test "rejects uppercase" do
      refute Slug.valid?("Brass_Bound_Chest")
    end

    test "rejects leading digit" do
      refute Slug.valid?("7_iron_chest")
    end

    test "rejects hyphen" do
      refute Slug.valid?("brass-bound-chest")
    end

    test "rejects UUID-shaped strings" do
      refute Slug.valid?("550e8400-e29b-41d4-a716-446655440000")
    end

    test "rejects > 64 characters" do
      refute Slug.valid?(String.duplicate("a", 65))
    end

    test "accepts exactly 64 characters" do
      assert Slug.valid?(String.duplicate("a", 64))
    end

    test "rejects non-binary values" do
      refute Slug.valid?(nil)
      refute Slug.valid?(:not_a_string)
      refute Slug.valid?(42)
    end
  end
end
