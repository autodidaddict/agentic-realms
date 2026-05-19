defmodule AgenticRealms.World.Communication.RecipientResolverTest do
  @moduledoc """
  Unit tests for case-insensitive recipient resolution shared by tell/whisper.
  Covers FR-010 (case-insensitive exact match, ambiguous refusal) and
  FR-010a (self-target refusal).
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Communication.RecipientResolver

  defp register!(name) do
    {:ok, p} = Accounts.register_player(%{username: name, password: "pw12345678"})
    p
  end

  test "resolves exact lowercase match" do
    suffix = unique()
    alice = register!("alice_#{suffix}")
    sender = register!("sender_#{suffix}")

    assert {:ok, %{id: id, username: name}} =
             RecipientResolver.resolve("alice_#{suffix}", sender.id)

    assert id == alice.id
    assert name == "alice_#{suffix}"
  end

  test "case-insensitive match returns the canonical (registered) casing" do
    suffix = unique()
    alice = register!("Alice_#{suffix}")
    sender = register!("sender_#{suffix}")

    assert {:ok, %{id: id, username: "Alice_" <> _}} =
             RecipientResolver.resolve("alice_#{suffix}", sender.id)

    assert id == alice.id
  end

  test ":not_found when no player matches" do
    sender = register!("sender_#{unique()}")
    assert {:error, :not_found} = RecipientResolver.resolve("nobody_#{unique()}", sender.id)
  end

  test ":self_target when resolved id matches sender id" do
    suffix = unique()
    sender = register!("alice_#{suffix}")

    assert {:error, :self_target} =
             RecipientResolver.resolve("alice_#{suffix}", sender.id)
  end

  test ":self_target is checked before ambiguity (pathological case)" do
    # Both "carol_X" and "CAROL_X" exist. Sender is carol_X. Resolution by
    # "carol_X" returns BOTH rows from the LOWER() query. Per FR-010a, the
    # self-target check should fire only when the result is a single row
    # matching the sender id; with multiple rows, ambiguous wins.
    suffix = unique()
    sender = register!("carol_#{suffix}")
    _other = register!("CAROL_#{suffix}")

    # With two matches, ambiguous (not self_target) — because the case clause
    # checks `[%{id: ^sender_id}]` (singleton) before `[_ | _]`.
    assert {:error, :ambiguous} = RecipientResolver.resolve("carol_#{suffix}", sender.id)
  end

  test ":ambiguous when two players share a case-insensitive username" do
    # AgenticRealms.Accounts.Player.unique_constraint is case-sensitive, so
    # `bob_X` and `BOB_X` can both be registered.
    suffix = unique()
    sender = register!("sender_#{suffix}")
    _bob = register!("bob_#{suffix}")
    _bob_caps = register!("BOB_#{suffix}")

    assert {:error, :ambiguous} = RecipientResolver.resolve("bob_#{suffix}", sender.id)
  end

  defp unique, do: System.unique_integer([:positive])
end
