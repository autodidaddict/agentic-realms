defmodule AgenticRealms.World.Communication.RecipientResolverTest do
  @moduledoc """
  Unit tests for case-insensitive recipient resolution shared by tell/whisper.
  Covers FR-010 (case-insensitive exact match, ambiguous refusal) and
  FR-010a (self-target refusal).

  Players are resolved by their character's name, so every
  fixture here registers an account and then gives it a character to be
  addressed by. The account username is no longer a way to reach anyone.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Communication.RecipientResolver

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
    suffix = unique()
    sender = register!("carol_#{suffix}")
    _other = collide!("CAROL_#{suffix}")

    assert {:error, :ambiguous} = RecipientResolver.resolve("carol_#{suffix}", sender.id)
  end

  test ":ambiguous when two characters share a case-insensitive name" do
    suffix = unique()
    sender = register!("sender_#{suffix}")
    _bob = register!("bob_#{suffix}")
    _bob_caps = collide!("BOB_#{suffix}")

    assert {:error, :ambiguous} = RecipientResolver.resolve("bob_#{suffix}", sender.id)
  end

  defp unique, do: System.unique_integer([:positive])
end
