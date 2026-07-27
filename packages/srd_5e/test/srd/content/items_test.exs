defmodule Srd.Content.ItemsTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Item
  alias Srd.Content.Items

  doctest Srd.Content.Items

  describe "all/0" do
    test "returns every item as a struct" do
      assert Enum.all?(Items.all(), &match?(%Item{}, &1))
    end

    test "covers the seven equipment packs" do
      assert length(Items.all(category: :pack)) == 7
    end

    test "covers the seventeen artisan's tools" do
      assert length(Items.all(category: :artisans_tools)) == 17
    end
  end

  describe "all/1" do
    test "filters by category" do
      assert Items.all(category: :musical_instrument) |> length() == 10

      assert Items.all(category: :focus) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["arcane-focus", "druidic-focus", "holy-symbol"]
    end

    test "raises on an unknown filter" do
      assert_raise ArgumentError, ~r/unknown item filter/, fn -> Items.all(colour: :red) end
    end
  end

  describe "get/1" do
    test "looks up a tool and the ability its checks use" do
      thieves_tools = Items.get("thieves-tools")
      assert thieves_tools.name == "Thieves' Tools"
      assert thieves_tools.category == :tool
      assert thieves_tools.ability == :dex
    end

    test "carries a pack's contents with quantities" do
      pack = Items.get("explorers-pack")
      assert %{item: "rations", quantity: 10} in pack.contents
      assert %{item: "torch", quantity: 10} in pack.contents
      assert %{item: "backpack", quantity: 1} in pack.contents
    end

    test "carries the forms a spellcasting focus can take" do
      assert "Sprig of mistletoe" in Items.get("druidic-focus").variants
      assert Items.get("holy-symbol").variants == ["Amulet", "Emblem", "Reliquary"]
    end

    test "returns nil for an unknown slug" do
      assert Items.get("vorpal-spork") == nil
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Items.fetch!("vorpal-spork") end
    end
  end

  test "every pack's contents resolve to real items" do
    for item <- Items.all(category: :pack), entry <- item.contents do
      assert Items.get(entry.item), "#{item.slug} names unknown item #{entry.item}"
    end
  end
end
