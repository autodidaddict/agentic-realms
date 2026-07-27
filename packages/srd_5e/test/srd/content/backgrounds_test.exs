defmodule Srd.Content.BackgroundsTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Background
  alias Srd.Content.Backgrounds
  alias Srd.Content.Bundle
  alias Srd.Content.Choice
  alias Srd.Content.Feats
  alias Srd.Rules.Skill

  doctest Srd.Content.Background
  doctest Srd.Content.Backgrounds

  describe "all/0" do
    test "returns the SRD's four backgrounds" do
      backgrounds = Backgrounds.all()
      assert length(backgrounds) == 4

      assert backgrounds |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["acolyte", "criminal", "sage", "soldier"]
    end
  end

  describe "all/1" do
    test "filters by granted skill" do
      assert Backgrounds.all(skill: :stealth) |> Enum.map(& &1.slug) == ["criminal"]
    end

    test "filters by raisable ability" do
      assert Backgrounds.all(ability: :str) |> Enum.map(& &1.slug) == ["soldier"]
    end
  end

  describe "effects" do
    test "each names three ability scores" do
      assert Enum.all?(Backgrounds.all(), &(length(&1.ability_scores) == 3))
    end

    test "each grants exactly two real skills" do
      for background <- Backgrounds.all() do
        assert length(background.skills) == 2
        assert Enum.all?(background.skills, &(&1 in Skill.all()))
      end
    end

    test "each grants a real origin feat" do
      for background <- Backgrounds.all() do
        feat = Feats.get(background.origin_feat)
        assert feat, "#{background.slug} names unknown feat #{background.origin_feat}"
        assert feat.category == :origin
      end
    end

    test "acolyte carries the option its feat is fixed to" do
      acolyte = Backgrounds.get("acolyte")
      assert acolyte.origin_feat == "magic-initiate"
      assert acolyte.origin_feat_option == "Cleric"
      assert Backgrounds.get("sage").origin_feat_option == "Wizard"
    end

    test "backgrounds whose feat takes no option leave it nil" do
      assert Backgrounds.get("criminal").origin_feat_option == nil
    end

    test "soldier chooses a gaming set while acolyte's tool is settled" do
      soldier = Backgrounds.get("soldier")
      assert soldier.tool.kind == :tool
      assert length(soldier.tool.from) == 4
      refute Choice.fixed?(soldier.tool)

      assert Choice.fixed?(Backgrounds.get("acolyte").tool)
      assert Backgrounds.get("acolyte").tool.from == ["calligraphers-supplies"]
    end
  end

  describe "starting equipment" do
    test "each offers a bundle or 50 GP" do
      for background <- Backgrounds.all() do
        assert %Choice{kind: :equipment, choose: 1, from: [bundle, gold]} = background.equipment
        assert %Bundle{} = bundle
        assert bundle.items != []
        assert gold.items == []
        assert gold.gp == 50
      end
    end

    test "criminal's bundle carries quantities" do
      [bundle, _gold] = Backgrounds.get("criminal").equipment.from
      assert %{item: "dagger", quantity: 2} = Enum.find(bundle.items, &(&1.item == "dagger"))
      assert bundle.gp == 16
    end

    test "a bundle can name which form an item takes" do
      [bundle, _gold] = Backgrounds.get("acolyte").equipment.from
      book = Enum.find(bundle.items, &(&1.item == "book"))
      assert book.variant == "Prayers"
    end

    test "every item in every bundle resolves" do
      for background <- Backgrounds.all(),
          bundle <- background.equipment.from,
          entry <- bundle.items do
        assert Bundle.known?(entry.item), "#{background.slug} names unknown item #{entry.item}"
      end
    end
  end

  describe "spreads/0" do
    test "is 2 and 1, or 1 to all three" do
      assert Background.spreads() == [[2, 1], [1, 1, 1]]
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Backgrounds.fetch!("pirate") end
    end
  end
end
