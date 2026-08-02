defmodule AgenticRealms.World.Communication.RecipientResolverTest do
  @moduledoc """
  Unit tests for case-insensitive recipient resolution shared by tell/whisper.
  Covers FR-010 (case-insensitive exact match, ambiguous refusal) and
  FR-010a (self-target refusal).

  Feature 021 — players are resolved by their character's name, so every
  fixture here registers an account and then gives it a character to be
  addressed by. The account username is no longer a way to reach anyone.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Communication.RecipientResolver

  # A character with a name that collides with one already in use. The creation
  # path refuses this, and rightly — but FR-013 permits it to arise from two
  # confirmations racing, so the resolver still has to cope. Written straight
  # into the projection because that is the only way to reach the state.
  defp collide!(name) do
    {:ok, p} =
      Accounts.register_player(%{
        username: "login_#{System.unique_integer([:positive])}",
        password: "pw12345678"
      })

    AgenticRealms.Repo.insert!(
      struct!(
        AgenticRealms.World.Schemas.PlayerState,
        [player_id: p.id] ++ AgenticRealms.DataCase.character_columns(character_name: name)
      )
    )

    p
  end

  # `name` becomes the character's name; the login is incidental and different.
  defp register!(name) do
    {:ok, p} =
      Accounts.register_player(%{
        username: "login_#{System.unique_integer([:positive])}",
        password: "pw12345678"
      })

    AgenticRealms.DataCase.create_character!(p.id, name: name)
    p
  end

  test "resolves exact lowercase match" do
    suffix = unique()
    alice = register!("alice_#{suffix}")
    sender = register!("sender_#{suffix}")

    assert {:ok, %{id: id, name: name}} =
             RecipientResolver.resolve("alice_#{suffix}", sender.id)

    assert id == alice.id
    assert name == "alice_#{suffix}"
  end

  test "case-insensitive match returns the canonical (registered) casing" do
    suffix = unique()
    alice = register!("Alice_#{suffix}")
    sender = register!("sender_#{suffix}")

    assert {:ok, %{id: id, name: "Alice_" <> _}} =
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
    _other = collide!("CAROL_#{suffix}")

    # With two matches, ambiguous (not self_target) — because the case clause
    # checks `[%{id: ^sender_id}]` (singleton) before `[_ | _]`.
    assert {:error, :ambiguous} = RecipientResolver.resolve("carol_#{suffix}", sender.id)
  end

  test ":ambiguous when two characters share a case-insensitive name" do
    # Creation refuses a name already in use, so this state can only arise from
    # the race FR-013 permits. The resolver still has to handle it rather than
    # picking one of the two arbitrarily.
    suffix = unique()
    sender = register!("sender_#{suffix}")
    _bob = register!("bob_#{suffix}")
    _bob_caps = collide!("BOB_#{suffix}")

    assert {:error, :ambiguous} = RecipientResolver.resolve("bob_#{suffix}", sender.id)
  end

  defp unique, do: System.unique_integer([:positive])
end
