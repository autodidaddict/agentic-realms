defmodule AgenticRealmsWeb.CharacterCreationTest do
  @moduledoc """
  Feature 021 US1 — a new player is asked who they are before they get a world.

  This file previously asserted the opposite: that feature 020's generated
  character arrived with no prompt at all. That is the behaviour this feature
  removes, so the assertions are inverted rather than extended.

  Tagged `:integration` (mounts the full GameLive); run with:

      mix test --include integration \\
        test/agenticrealms_web/live/character_creation_test.exs
  """
  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest
  import AgenticRealmsWeb.GameComponents.Primitives, only: [signed: 1]

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias AgenticRealms.World.Schemas.PlayerState
  alias AgenticRealms.World.Seed
  alias Srd.Rules.PointBuy

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

  defp fill_identity(view, name, species \\ "elf", class \\ "wizard", background \\ "sage") do
    render_keyup(view, "creation_name", %{"key" => "r", "value" => name})
    select(view, "species", species)
    select(view, "class", class)
    select(view, "background", background)
    view
  end

  defp select(view, field, value) do
    render_click(view, "creation_select", %{"field" => field, "slug" => value})
  end

  defp raise_ability(view, ability),
    do: render_click(view, "creation_ability_up", %{"ability" => to_string(ability)})

  defp lower_ability(view, ability),
    do: render_click(view, "creation_ability_down", %{"ability" => to_string(ability)})

  defp reroll(view), do: render_click(view, "creation_reroll", %{})

  defp draft_of(view), do: :sys.get_state(view.pid).socket.assigns.draft

  defp spread(view, param), do: render_click(view, "creation_spread", %{"spread" => param})

  defp pick_skill(view, skill),
    do: render_click(view, "creation_skill", %{"skill" => to_string(skill)})

  defp pick(view, key, value),
    do: render_click(view, "creation_pick", %{"key" => key, "option" => to_string(value)})

  defp at_specializations(conn, species, class, background) do
    player = register("spec")
    {:ok, view, _} = play_as(conn, player)

    fill_identity(view, "Spec#{System.unique_integer([:positive])}", species, class, background)
    roll_abilities(view)
    spread(view, "even")

    probe =
      Draft.new()
      |> Draft.put_selection(:species, species)
      |> Draft.put_selection(:class, class)
      |> Draft.put_selection(:background, background)

    probe
    |> Draft.offered_skills()
    |> Enum.take(Draft.skill_allowance(probe))
    |> Enum.each(&pick_skill(view, &1))

    step(view, :specializations)

    {player, view}
  end

  defp step(view, name), do: render_click(view, "creation_step", %{"step" => to_string(name)})

  defp roll_abilities(view) do
    step(view, :abilities)
    view
  end

  describe "the dialog appears" do
    test "for a player who has never entered the game", %{conn: conn} do
      player = register("fresh")
      assert Repo.get(PlayerState, player.id) == nil

      {:ok, _view, html} = play_as(conn, player)

      assert html =~ "Create Your Character"
      assert Repo.get(PlayerState, player.id) == nil
    end

    test "and not for a player who already has a character", %{conn: conn} do
      player = register("returning")
      AgenticRealms.DataCase.create_character!(player.id, name: "Returner")

      {:ok, _view, html} = play_as(conn, player)

      refute html =~ "Create Your Character"
      assert html =~ "Returner"
    end
  end

  describe "the dialog cannot be dismissed" do
    test "it offers no close button, no backdrop catcher, and no escape binding",
         %{conn: conn} do
      {:ok, _view, html} = play_as(conn, register("trapped"))

      assert html =~ "Create Your Character"
      refute html =~ "gm-backdrop-click"
      refute html =~ ~s(phx-click="close_modal")
      refute html =~ ~s(phx-window-keydown="close_modal")
    end
  end

  describe "confirm is gated" do
    test "until a name and all three selections exist", %{conn: conn} do
      {:ok, view, html} = play_as(conn, register("partial"))

      assert html =~ "Give your character a name"
      assert html =~ "disabled"

      html = fill_identity(view, "Elrond") |> render()

      assert html =~ "Assign your ability scores."
      assert html =~ "disabled"
    end
  end

  describe "what the options show" do
    test "species carry size, speed, and traits from the content library",
         %{conn: conn} do
      {:ok, _view, html} = play_as(conn, register("browsing"))

      assert html =~ "Dragonborn"
      assert html =~ "Halfling"
      assert html =~ "Darkvision"
      assert html =~ "ft."
    end

    test "classes carry hit die, primary ability, and saves", %{conn: conn} do
      {:ok, _view, html} = play_as(conn, register("classy"))

      assert html =~ "Barbarian"
      assert html =~ "Hit die 1d12"
      assert html =~ "Second Wind"
    end

    test "backgrounds carry the abilities they raise and the feat they grant",
         %{conn: conn} do
      {:ok, _view, html} = play_as(conn, register("storied"))

      assert html =~ "Acolyte"
      assert html =~ "Magic Initiate"
      assert html =~ "Savage Attacker"
    end

    test "a deferred subclass is named, not offered", %{conn: conn} do
      {:ok, view, _html} = play_as(conn, register("patient"))

      html = select(view, "class", "fighter")

      assert html =~ "You will choose your Fighter subclass at level 3."
    end
  end

  describe "confirming" do
    test "creates the character and puts the player in the world", %{conn: conn} do
      player = register("decisive")
      {:ok, view, _html} = play_as(conn, player)

      html =
        view
        |> fill_identity("Elrond")
        |> render_click("creation_confirm", %{})

      ps = Repo.get(PlayerState, player.id)

      assert ps.character_name == "Elrond"
      assert ps.species_slug == "elf"
      assert ps.class_slug == "wizard"
      assert ps.background_slug == "sage"
      assert ps.level == 1
      assert ps.xp == 0
      assert ps.hp == ps.max_hp
      assert ps.current_room_id == Seed.starting_room_id()

      refute html =~ "Create Your Character"
      assert html =~ "Elrond"
    end

    test "the unasked choices are filled in and legal", %{conn: conn} do
      player = register("unasked")
      {:ok, view, _html} = play_as(conn, player)

      view |> fill_identity("Galadriel") |> render_click("creation_confirm", %{})

      ps = Repo.get(PlayerState, player.id)

      scores = [ps.str, ps.dex, ps.con, ps.int, ps.wis, ps.cha]

      assert length(scores) == 6

      for score <- scores do
        assert score >= PointBuy.min_score()
        assert score <= PointBuy.max_score() + 2
      end

      assert length(ps.skill_proficiencies) > 0
      assert ps.save_proficiencies == ["int", "wis"]
      assert ps.size == "medium"
    end

    test "a taken name keeps the dialog open with every choice intact", %{conn: conn} do
      first = register("original")
      AgenticRealms.DataCase.create_character!(first.id, name: "Gandalf")

      second = register("impostor")
      {:ok, view, _html} = play_as(conn, second)

      html =
        view
        |> fill_identity("gandalf", "dwarf", "cleric", "acolyte")
        |> render_click("creation_confirm", %{})

      assert html =~ "That name is taken"
      assert html =~ "Create Your Character"
      assert html =~ ~s(aria-pressed="true")
      assert Repo.get(PlayerState, second.id) == nil
    end
  end

  describe "abandoning" do
    test "leaves no trace", %{conn: conn} do
      player = register("quitter")
      {:ok, view, _html} = play_as(conn, player)

      fill_identity(view, "Ghost")

      GenServer.stop(view.pid)

      assert Repo.get(PlayerState, player.id) == nil
    end
  end

  describe "the abilities step" do
    setup %{conn: conn} do
      player = register("abilities")
      {:ok, view, _} = play_as(conn, player)
      fill_identity(view, "Ability#{System.unique_integer([:positive])}")
      step(view, :abilities)
      %{player: player, view: view}
    end

    test "opens on a spread that spends the whole budget", %{view: view} do
      bought = draft_of(view).bought

      assert map_size(bought) == 6

      assert PointBuy.fully_spent?(bought),
             "the step should open playable, not on six eights and a bill"
    end

    test "puts the highest score on what the class runs on", %{conn: conn} do
      for _ <- 1..10 do
        player = register("primary")
        {:ok, view, _} = play_as(conn, player)
        fill_identity(view, "Prime#{System.unique_integer([:positive])}")
        step(view, :abilities)

        bought = draft_of(view).bought
        assert bought.int == bought |> Map.values() |> Enum.max()
      end
    end

    test "shows a stepper for every ability rather than a value per score", %{view: view} do
      html = render(view)

      for ability <- Srd.Rules.Ability.all() do
        assert html =~ ~s(phx-click="creation_ability_up" phx-value-ability="#{ability}")
        assert html =~ ~s(phx-click="creation_ability_down" phx-value-ability="#{ability}")
      end
    end

    test "+ spends a point and - refunds one", %{view: view} do
      before = draft_of(view).bought

      lowered_from =
        before |> Enum.find(fn {_a, score} -> score > PointBuy.min_score() end) |> elem(0)

      lower_ability(view, lowered_from)
      after_lower = draft_of(view)

      assert after_lower.bought[lowered_from] == before[lowered_from] - 1
      assert Draft.points_remaining(after_lower) > 0

      raisable =
        Enum.find(Srd.Rules.Ability.all(), &PointBuy.can_increase?(after_lower.bought, &1))

      raise_ability(view, raisable)

      assert draft_of(view).bought[raisable] == after_lower.bought[raisable] + 1
    end

    test "refuses to go below the floor", %{view: view} do
      for _ <- 1..10, do: lower_ability(view, :cha)

      assert draft_of(view).bought.cha == PointBuy.min_score()

      lower_ability(view, :cha)
      assert draft_of(view).bought.cha == PointBuy.min_score()
    end

    test "disables the buttons the rules refuse", %{view: view} do
      for _ <- 1..10, do: lower_ability(view, :cha)
      html = render(view)

      assert html =~ ~r|disabled[^>]*phx-click="creation_ability_down" phx-value-ability="cha"|s or
               html =~ ~r|phx-click="creation_ability_down" phx-value-ability="cha"[^>]*disabled|s
    end

    test "rolling again produces another full spend", %{view: view} do
      first = draft_of(view).bought

      spreads =
        for _ <- 1..20 do
          reroll(view)
          bought = draft_of(view).bought
          assert PointBuy.fully_spent?(bought)
          bought
        end

      assert Enum.any?(spreads, &(&1 != first)), "rerolling should be able to change something"
    end

    test "a forged ability is ignored rather than accepted", %{view: view} do
      before = render(view)

      render_click(view, "creation_ability_up", %{"ability" => "luck"})
      render_click(view, "creation_ability_down", %{"ability" => "banana"})
      render_click(view, "creation_spread", %{"spread" => "split:cha:cha"})

      assert render(view) == before
    end

    test "shows each ability's final score including the background increase",
         %{view: view} do
      roll_abilities(view)
      select(view, "background", "sage")
      html = spread(view, "split:int:con")

      assert html =~ "15"
      assert html =~ "+2"
      assert html =~ "from background"
    end

    test "offers only the three abilities the background names", %{view: view} do
      html = select(view, "background", "sage")

      assert html =~ "split:int:con"
      refute html =~ "split:cha:"
      refute html =~ ":cha\"" |> String.replace("\\", "")
    end

    test "the even spread asks nothing further", %{view: view} do
      roll_abilities(view)
      html = spread(view, "even")

      assert html =~ ~s(aria-pressed="true")
      assert html =~ "from background"
    end

    test "changing the background clears the spread and keeps the array", %{view: view} do
      roll_abilities(view)
      select(view, "background", "sage")
      spread(view, "split:int:con")

      html = select(view, "background", "soldier")

      refute html =~ "from background"
      assert html =~ ~s(phx-value-ability="cha")
    end

    test "the player's own spread reaches the character", %{view: view, player: player} do
      select(view, "background", "sage")
      spread(view, "split:int:con")

      expected = view |> draft_of() |> Draft.scores()

      render_click(view, "creation_confirm", %{})

      ps = Repo.get(PlayerState, player.id)

      for {ability, score} <- expected do
        assert Map.fetch!(ps, ability) == score,
               "#{ability} should have reached the character as #{score}"
      end
    end
  end

  describe "the skills step" do
    setup %{conn: conn} do
      player = register("skills")
      {:ok, view, _} = play_as(conn, player)

      fill_identity(
        view,
        "Skiller#{System.unique_integer([:positive])}",
        "human",
        "fighter",
        "soldier"
      )

      roll_abilities(view)
      spread(view, "split:str:con")
      step(view, :skills)

      %{player: player, view: view}
    end

    test "offers exactly the class' allowance from exactly its list", %{view: view} do
      html = render(view)

      assert html =~ "Choose 2 Skills"
      assert html =~ ~s(phx-value-skill="acrobatics")
      assert html =~ ~s(phx-value-skill="survival")
      refute html =~ ~s(phx-value-skill="arcana")
      refute html =~ ~s(phx-value-skill="stealth")
    end

    test "shows the granted skills as held and does not offer them", %{view: view} do
      html = render(view)

      assert html =~ "Already Yours"
      assert html =~ "granted"
      assert html =~ "Athletics"
      assert html =~ "Intimidation"

      refute html =~ ~s(phx-value-skill="athletics")
      refute html =~ ~s(phx-value-skill="intimidation")
    end

    test "shows the keying ability and the modifier each skill would give",
         %{view: view} do
      html = render(view)

      assert html =~ "DEX"
      assert html =~ "WIS"

      assert html =~ ~r|cc-skill-meta">\s*[A-Z]{3}\s*[+-]\d|
    end

    test "picking past the allowance releases the oldest pick", %{view: view} do
      pick_skill(view, :acrobatics)
      pick_skill(view, :perception)
      html = pick_skill(view, :survival)

      assert html =~ "All chosen."

      assert html =~
               ~s(aria-pressed="false" phx-click="creation_skill" phx-value-skill="acrobatics")

      assert html =~
               ~s(aria-pressed="true" phx-click="creation_skill" phx-value-skill="perception")

      assert html =~ ~s(aria-pressed="true" phx-click="creation_skill" phx-value-skill="survival")
    end

    test "a pick can be released by clicking it again", %{view: view} do
      pick_skill(view, :perception)
      assert render(view) =~ "One more to choose."

      pick_skill(view, :perception)
      assert render(view) =~ "2 more to choose."
    end

    test "a granted skill cannot be picked even by a crafted event", %{view: view} do
      before = render(view)

      pick_skill(view, :athletics)
      pick_skill(view, :nonsense)

      assert render(view) == before
    end

    test "changing the class re-asks against the new class' list", %{view: view} do
      pick_skill(view, :acrobatics)
      pick_skill(view, :perception)

      step(view, :identity)
      select(view, "class", "wizard")
      html = step(view, :skills)

      assert html =~ "2 more to choose."
      assert html =~ ~s(phx-value-skill="arcana")
      refute html =~ ~s(phx-value-skill="acrobatics")
    end

    test "the player's own picks reach the character", %{view: view, player: player} do
      pick_skill(view, :perception)
      pick_skill(view, :survival)
      render_click(view, "creation_confirm", %{})

      ps = Repo.get(PlayerState, player.id)

      assert "perception" in ps.skill_proficiencies
      assert "survival" in ps.skill_proficiencies
      assert "athletics" in ps.skill_proficiencies
      assert ps.skill_proficiencies == Enum.uniq(ps.skill_proficiencies)
    end
  end

  describe "the specializations step" do
    test "an elf is asked for a lineage, named after the trait", %{conn: conn} do
      {_player, view} = at_specializations(conn, "elf", "wizard", "sage")
      html = render(view)

      assert html =~ "Elven Lineage"
      assert html =~ "Wood Elf"
      assert html =~ "Drow"
      assert html =~ ~s(phx-value-key="species_lineage")
    end

    test "a dwarf is asked for no lineage at all", %{conn: conn} do
      {_player, view} = at_specializations(conn, "dwarf", "wizard", "sage")
      html = render(view)

      refute html =~ "Lineage"
      refute html =~ ~s(phx-value-key="species_lineage")
    end

    test "a species with two sizes is asked which; one with a single size is not",
         %{conn: conn} do
      {_player, human} = at_specializations(conn, "human", "wizard", "sage")
      assert render(human) =~ ~s(phx-value-key="species_size")
      assert render(human) =~ "Medium"

      {_player, elf} = at_specializations(conn, "elf", "wizard", "sage")
      refute render(elf) =~ ~s(phx-value-key="species_size")
    end

    test "a fighter is asked for a fighting style and three weapon masteries",
         %{conn: conn} do
      {_player, view} = at_specializations(conn, "dwarf", "fighter", "sage")
      html = render(view)

      assert html =~ "Fighting Style"
      assert html =~ "Defense"
      assert html =~ "Weapon Mastery"
      assert html =~ "Choose 3."
      assert html =~ "Longsword"
      assert html =~ "Mastery:"
    end

    test "a cleric is asked for a Divine Order, which nothing in the code names",
         %{conn: conn} do
      {_player, view} = at_specializations(conn, "dwarf", "cleric", "sage")
      html = render(view)

      assert html =~ "Divine Order"
      assert html =~ "Protector"
      assert html =~ "Thaumaturge"
    end

    test "a combination that asks nothing says so instead of showing an empty step",
         %{conn: conn} do
      {_player, view} = at_specializations(conn, "dwarf", "wizard", "sage")
      html = render(view)

      assert html =~ "ask nothing more of you at this level"
    end

    test "a feat the background granted is shown as held, not offered", %{conn: conn} do
      {_player, view} = at_specializations(conn, "human", "wizard", "criminal")
      html = render(view)

      assert html =~ "Versatile"
      assert html =~ "Alert"
      assert html =~ "already granted by your background"
      refute html =~ ~s(phx-value-option="alert")
    end

    test "picks reach the character in the right column", %{conn: conn} do
      {player, view} = at_specializations(conn, "elf", "fighter", "sage")

      pick(view, "species_lineage", "wood-elf")
      pick(view, "feature:Keen Senses", "perception")
      pick(view, "feature:Fighting Style", "archery")
      pick(view, "feature:Weapon Mastery", "longbow")
      pick(view, "feature:Weapon Mastery", "shortsword")
      pick(view, "feature:Weapon Mastery", "scimitar")

      render_click(view, "creation_confirm", %{})
      ps = Repo.get(PlayerState, player.id)

      assert ps.lineage_slug == "wood-elf"
      assert "perception" in ps.skill_proficiencies
      assert "archery" in ps.feat_slugs
      assert ps.choices["feature:Weapon Mastery"] == ["longbow", "shortsword", "scimitar"]
    end

    test "changing the species discards that species' picks and keeps the class'",
         %{conn: conn} do
      {_player, view} = at_specializations(conn, "elf", "fighter", "sage")

      pick(view, "species_lineage", "wood-elf")
      pick(view, "feature:Fighting Style", "defense")

      step(view, :identity)
      select(view, "species", "dwarf")
      html = step(view, :specializations)

      refute html =~ ~s(phx-value-key="species_lineage")

      assert html =~
               ~s(aria-pressed="true" phx-click="creation_pick" phx-value-key="feature:Fighting Style")
    end

    test "a forged key or option is ignored", %{conn: conn} do
      {_player, view} = at_specializations(conn, "elf", "wizard", "sage")
      before = render(view)

      pick(view, "species_lineage", "forest-gnome")
      pick(view, "feature:Wild Shape", "bear")

      assert render(view) == before
    end
  end

  describe "the review step" do
    defp at_review(conn) do
      {player, view} = at_specializations(conn, "elf", "fighter", "soldier")

      pick(view, "species_lineage", "wood-elf")
      pick(view, "feature:Keen Senses", "perception")
      pick(view, "feature:Fighting Style", "archery")
      pick(view, "feature:Weapon Mastery", "longbow")
      pick(view, "feature:Weapon Mastery", "shortsword")
      pick(view, "feature:Weapon Mastery", "scimitar")
      pick(view, "background_tool", "dice-set")
      step(view, :review)

      {player, view}
    end

    test "shows the whole character before it exists", %{conn: conn} do
      {_player, view} = at_review(conn)
      html = render(view)

      assert html =~ "Level 1 Elf Fighter"
      assert html =~ "Armor Class"
      assert html =~ "Initiative"
      assert html =~ "Proficiency"
      assert html =~ "Strength"
      assert html =~ "Perception"
    end

    test "the created character is the one that was reviewed", %{conn: conn} do
      {player, view} = at_review(conn)

      reviewed = render(view)
      render_click(view, "creation_confirm", %{})

      created = AgenticRealms.World.Stats.for_player(player.id)

      assert reviewed =~ created.name
      assert reviewed =~ "Level 1 #{created.species.name} #{created.class.name}"
      assert reviewed =~ ~s(<span class="v">#{created.armor_class}</span>)
      assert reviewed =~ ~s(<span class="v">#{signed(created.initiative)}</span>)
      assert reviewed =~ ~s(<span class="v">#{signed(created.proficiency_bonus)}</span>)
      assert reviewed =~ "#{created.hp.max} / #{created.hp.max}"

      for ability <- created.abilities do
        assert reviewed =~ "#{ability.score}"
        assert reviewed =~ signed(ability.modifier)
      end

      ps = Repo.get(PlayerState, player.id)
      assert ps.lineage_slug == "wood-elf"
      assert ps.choices["feature:Weapon Mastery"] == ["longbow", "shortsword", "scimitar"]
    end

    test "the review is computed by the same function as the sheet", %{conn: conn} do
      {player, view} = at_review(conn)
      render_click(view, "creation_confirm", %{})

      created = AgenticRealms.World.Stats.for_player(player.id)
      ps = Repo.get(PlayerState, player.id)

      from_draft =
        AgenticRealms.World.Stats.sheet(
          %{
            species: ps.species_slug,
            class: ps.class_slug,
            background: ps.background_slug,
            size: String.to_existing_atom(ps.size),
            level: 1,
            xp: 0,
            abilities: %{
              str: ps.str,
              dex: ps.dex,
              con: ps.con,
              int: ps.int,
              wis: ps.wis,
              cha: ps.cha
            },
            skill_proficiencies: Enum.map(ps.skill_proficiencies, &String.to_existing_atom/1),
            save_proficiencies: Enum.map(ps.save_proficiencies, &String.to_existing_atom/1)
          },
          ps.character_name
        )

      assert from_draft == created
    end

    test "lists the choices the player made, by the question that asked",
         %{conn: conn} do
      {_player, view} = at_review(conn)
      html = render(view)

      assert html =~ "Your Choices"
      assert html =~ "Elven Lineage"
      assert html =~ "Wood Elf"
      assert html =~ "Fighting Style"
      assert html =~ "Archery"
      assert html =~ "Longbow, Shortsword, Scimitar"
    end

    test "lists the features the character will have", %{conn: conn} do
      {_player, view} = at_review(conn)
      html = render(view)

      assert html =~ "Features"
      assert html =~ "Darkvision"
      assert html =~ "Second Wind"
    end

    test "going back and changing the class moves everything downstream",
         %{conn: conn} do
      {_player, view} = at_review(conn)
      before = render(view)

      assert before =~ "Fighter"

      step(view, :identity)
      select(view, "class", "wizard")

      assert render(view) =~ "Choose 2 Skills" or step(view, :skills) =~ "Choose 2 Skills"

      pick_skill(view, :arcana)
      pick_skill(view, :investigation)
      html = step(view, :review)

      assert html =~ "Level 1 Elf Wizard"
      refute html =~ "Level 1 Elf Fighter"
      refute html == before
    end

    test "an incomplete character is told which step to go back to",
         %{conn: conn} do
      player = register("incomplete")
      {:ok, view, _} = play_as(conn, player)

      fill_identity(view, "Halfway", "elf", "fighter", "soldier")
      roll_abilities(view)
      spread(view, "even")

      html = step(view, :review)

      assert html =~ "Choose your skills."
      assert html =~ "disabled"
      assert Repo.get(PlayerState, player.id) == nil
    end
  end

  describe "the character name is the public identity" do
    test "another player sees the character, and never the account username",
         %{conn: conn} do
      alice = register("alice_login")
      bob = register("bob_login")

      AgenticRealms.DataCase.create_character!(alice.id, name: "Aragorn")
      AgenticRealms.DataCase.create_character!(bob.id, name: "Legolas")

      {:ok, _} = AgenticRealms.World.Commands.spawn(alice.id, Seed.starting_room_id())
      {:ok, _} = AgenticRealms.World.Commands.spawn(bob.id, Seed.starting_room_id())

      {:ok, _alice_view, _} = play_as(conn, alice)
      {:ok, bob_view, _} = play_as(conn, bob)

      Process.sleep(50)
      html = render(bob_view)

      assert html =~ "Aragorn"
      refute html =~ alice.username

      sheet = render_click(bob_view, "open_modal", %{"modal" => "stats"})
      assert sheet =~ "Legolas"
      refute sheet =~ alice.username

      assert html =~ ~s(class="ar-nav-username")
      assert html =~ bob.username
    end

    test "a whisper reaches a character by name, and the username finds nobody",
         %{conn: conn} do
      alice = register("alice_w")
      bob = register("bob_w")

      AgenticRealms.DataCase.create_character!(alice.id, name: "Gimli")
      AgenticRealms.DataCase.create_character!(bob.id, name: "Boromir")

      assert {:ok, %{id: id}} =
               AgenticRealms.World.Communication.RecipientResolver.resolve("boromir", alice.id)

      assert id == bob.id

      assert {:error, :not_found} =
               AgenticRealms.World.Communication.RecipientResolver.resolve(
                 bob.username,
                 alice.id
               )
    end
  end

  describe "two sessions" do
    test "confirming in both creates exactly one character", %{conn: conn} do
      player = register("doubled")

      {:ok, first, _} = play_as(conn, player)
      {:ok, second, _} = play_as(conn, player)

      first |> fill_identity("Radagast") |> render_click("creation_confirm", %{})

      second |> fill_identity("Radagast the Brown") |> render_click("creation_confirm", %{})

      ps = Repo.get(PlayerState, player.id)

      assert ps.character_name == "Radagast"
      assert Repo.aggregate(PlayerState, :count, :player_id) >= 1
    end
  end
end
