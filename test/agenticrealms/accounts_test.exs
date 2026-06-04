defmodule AgenticRealms.AccountsTest do
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.Accounts.Player

  describe "promote_to_wizard/1" do
    test "promotes a non-wizard player" do
      {:ok, %Player{id: id, is_wizard: false}} =
        Accounts.register_player(%{username: "promotee", password: "password123"})

      assert {:ok, %Player{id: ^id, is_wizard: true}} = Accounts.promote_to_wizard(id)
    end

    test "is idempotent for already-wizard players" do
      {:ok, %Player{id: id}} =
        Accounts.register_player(%{username: "twice_wizard", password: "password123"})

      {:ok, %Player{is_wizard: true}} = Accounts.promote_to_wizard(id)
      assert {:ok, %Player{is_wizard: true}} = Accounts.promote_to_wizard(id)
    end

    test "returns {:error, :not_found} for an unknown player id" do
      assert {:error, :not_found} = Accounts.promote_to_wizard(999_999_999)
    end
  end
end
