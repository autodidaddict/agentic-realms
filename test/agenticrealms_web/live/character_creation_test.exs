defmodule AgenticRealmsWeb.CharacterCreationTest do
  @moduledoc """
  Feature 020 US2 — a new player reaches the world with a complete character,
  with no prompt and no interactive step.

  Tagged `:integration` (mounts the full GameLive); run with:

      mix test --include integration \\
        test/agenticrealms_web/live/character_creation_test.exs
  """
  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Repo
  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}
  alias AgenticRealms.World.Schemas.PlayerState

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})
    %{conn: conn}
  end

  defp register(name) do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "#{name}_#{suffix}", password: "pw12345678"})
    p
  end

  defp play_as(conn, player) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player.id)
    |> live(~p"/play")
  end

  test "entering the world creates a complete character", %{conn: conn} do
    player = register("fresh")
    assert Repo.get(PlayerState, player.id) == nil

    {:ok, _view, _html} = play_as(conn, player)

    ps = Repo.get(PlayerState, player.id)

    assert ps.species_slug == "human"
    assert ps.class_slug == "fighter"
    assert ps.background_slug == "soldier"
    assert ps.size == "medium"
    assert {ps.str, ps.dex, ps.con, ps.int, ps.wis, ps.cha} == {17, 13, 15, 12, 10, 8}
    assert ps.level == 1
    assert ps.xp == 0
    assert ps.hp == 12
    assert ps.max_hp == 12

    assert ps.skill_proficiencies == [
             "acrobatics",
             "athletics",
             "history",
             "intimidation",
             "perception"
           ]

    assert ps.save_proficiencies == ["con", "str"]
    assert Enum.sort(ps.feat_slugs) == ["alert", "savage-attacker"]
  end

  test "the character exists alongside a current room, not instead of one", %{conn: conn} do
    player = register("placed")

    {:ok, _view, _html} = play_as(conn, player)

    ps = Repo.get(PlayerState, player.id)
    assert ps.current_room_id == Seed.starting_room_id()
    assert ps.species_slug == "human"
  end

  test "creation is deterministic across players", %{conn: conn} do
    one = register("twin_a")
    two = register("twin_b")

    {:ok, _, _} = play_as(conn, one)
    {:ok, _, _} = play_as(conn, two)

    character = fn p ->
      Repo.get(PlayerState, p.id)
      |> Map.take([:species_slug, :class_slug, :background_slug, :str, :dex, :con, :max_hp])
    end

    assert character.(one) == character.(two)
  end

  test "a second mount creates nothing new and disturbs nothing", %{conn: conn} do
    player = register("returning")

    {:ok, _, _} = play_as(conn, player)

    # Earn some progress, then come back.
    Repo.update_all(PlayerState, set: [level: 4, xp: 3_000])

    assert {:ok, :already_created} = Commands.ensure_character(player.id)

    {:ok, _, _} = play_as(conn, player)

    ps = Repo.get(PlayerState, player.id)
    assert ps.level == 4
    assert ps.xp == 3_000
  end

  test "no prompt or form appears on the way in", %{conn: conn} do
    player = register("unprompted")

    {:ok, _view, html} = play_as(conn, player)

    refute html =~ ~r/choose your (species|class|background)/i
    refute html =~ "Create your character"
    # Straight into the world.
    assert html =~ "Level 1 Human Fighter"
  end
end
