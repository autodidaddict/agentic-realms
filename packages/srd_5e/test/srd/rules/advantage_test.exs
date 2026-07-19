defmodule Srd.Rules.AdvantageTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Advantage

  describe "net/1" do
    test "no sources is normal" do
      assert Advantage.net([]) == :normal
    end

    test "advantage sources don't stack" do
      assert Advantage.net([:advantage, :advantage]) == :advantage
    end

    test "disadvantage sources don't stack" do
      assert Advantage.net([:disadvantage, :disadvantage]) == :disadvantage
    end

    test "any advantage with any disadvantage cancels to normal" do
      assert Advantage.net([:advantage, :disadvantage, :advantage]) == :normal
    end
  end
end
