defmodule Srd.Content.ChoiceTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Choice
  alias Srd.Content.Feature

  doctest Srd.Content.Choice

  describe "new/1" do
    test "keeps a literal list of options" do
      choice = Choice.new(%{kind: :skill, choose: 2, from: [:stealth, :arcana]})
      assert choice.from == [:stealth, :arcana]
    end

    test "expands an item category to slugs" do
      choice = Choice.new(%{kind: :tool, choose: 1, from: {:items, :gaming_set}})

      assert choice.from == [
               "dice-set",
               "dragonchess-set",
               "playing-card-set",
               "three-dragon-ante-set"
             ]
    end

    test "expands a feat category to slugs" do
      choice = Choice.new(%{kind: :feat, choose: 1, from: {:feats, :origin}})
      assert choice.from == ["alert", "magic-initiate", "savage-attacker", "skilled"]
    end

    test "expands weapon filters to slugs" do
      choice = Choice.new(%{kind: :weapon, choose: 2, from: {:weapons, category: :simple}})
      assert "club" in choice.from
      refute "greatsword" in choice.from
    end

    test "raises on an unknown kind" do
      assert_raise ArgumentError, ~r/unknown choice kind/, fn ->
        Choice.new(%{kind: :haircut, choose: 1, from: []})
      end
    end
  end

  describe "options/1" do
    test "returns what there is to pick from" do
      choice = Choice.new(%{kind: :feature, choose: 1, from: ["Protector", "Thaumaturge"]})
      assert Choice.options(choice) == ["Protector", "Thaumaturge"]
    end
  end

  describe "fixed?/1" do
    test "is true when there is nothing left to decide" do
      assert Choice.fixed?(Choice.new(%{kind: :tool, choose: 1, from: ["thieves-tools"]}))
    end

    test "is false when the options outnumber the picks" do
      refute Choice.fixed?(Choice.new(%{kind: :skill, choose: 1, from: [:stealth, :arcana]}))
    end
  end

  describe "Feature.through_level/2" do
    test "keeps features with no level, which arrive with the thing granting them" do
      features = [
        Feature.new(%{name: "Benefit", text: "Always yours."}),
        Feature.new(%{name: "Later", text: "At level 5.", level: 5})
      ]

      assert Feature.through_level(features, 1) |> Enum.map(& &1.name) == ["Benefit"]
      assert Feature.through_level(features, 5) |> Enum.map(& &1.name) == ["Benefit", "Later"]
    end

    test "sorts by level" do
      features = [
        Feature.new(%{name: "Third", text: "-", level: 7}),
        Feature.new(%{name: "First", text: "-", level: 1}),
        Feature.new(%{name: "Second", text: "-", level: 3})
      ]

      assert Feature.through_level(features, 20) |> Enum.map(& &1.name) ==
               ["First", "Second", "Third"]
    end
  end
end
