defmodule AgenticRealmsWeb.WizardNpcAuthoringTest do
  @moduledoc """
  Feature 015 US1/US2 — the wizard authors an NPC blueprint in trance (lore +
  composable toolsets), commits it (unified registry, kind badge), and spawns
  it into the room (witnessed arrival; the clone carries the composed
  behaviors).

  Tagged `:integration` and excluded from the default `mix test` run.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.{Accounts, Repo}
  alias AgenticRealms.World.{Commands, Queries, Seed}
  alias AgenticRealms.World.Schemas.{NPCClone, Toolset}

  @greeter %{
    "trigger" => "player_entered",
    "actions" => [%{"type" => "say", "text" => "Welcome, traveller."}]
  }

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %Toolset{
        name: "greeter",
        behaviors: [@greeter],
        applies_to: ["npc"],
        inserted_at: now,
        updated_at: now
      },
      on_conflict: :nothing,
      conflict_target: :name
    )

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, witness} =
      Accounts.register_player(%{username: "wit_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(witness.id, Seed.starting_room_id())

    %{
      wizard: wizard,
      wizard_conn: conn_for(conn, wizard.id),
      witness_conn: conn_for(conn, witness.id),
      suffix: suffix
    }
  end

  test "author an NPC in trance (lore + toolset) → commit → npc-kind row + registry badge",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    name = "cave troll #{suffix}"

    stub_tool_use("draft_npc_blueprint", %{
      "name" => name,
      "short_description" => "a hulking cave troll",
      "long_description" => "A mountain of grey muscle and warty hide.",
      "lore" => "Hates sunlight; speaks in short grunts.",
      "toolsets" => ["greeter"]
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a cave troll that greets"})
    |> render_submit()

    await_wizard_unlock(view)

    html = render(view)
    # Draft card populated, incl. the NPC-only lore field + toolset picker.
    assert html =~ name
    assert html =~ "Lore"
    assert html =~ "Hates sunlight"
    assert html =~ "greeter"

    render_hook(view, "commit_blueprint_draft", %{})

    expected_slug = name |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    bp = Queries.get_npc_blueprint_row(expected_slug)
    assert bp.kind == "npc"
    assert bp.revision == 1
    assert bp.lore =~ "Hates sunlight"
    assert bp.toolsets == ["greeter"]

    html = render(view)
    assert html =~ name
    assert html =~ ~s(data-testid="blueprint-kind-#{expected_slug}")
  end

  test "spawn an authored NPC → witnessed arrival; clone carries composed behaviors",
       %{wizard: wizard, wizard_conn: wzc, witness_conn: wtc, suffix: suffix} do
    slug = "ogre_#{suffix}"

    {:ok, ^slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "Mossback the Ogre",
        short_description: "a moss-covered ogre",
        long_description: "A lumbering ogre draped in river moss.",
        lore: "Guards the old bridge.",
        toolsets: ["greeter"]
      })

    {:ok, wizard_view, _} = live(wzc, ~p"/play")
    {:ok, witness_view, _} = live(wtc, ~p"/play")

    render_hook(wizard_view, "switch_mode", %{"mode" => "wizard"})

    # World mode exposes the Spawn here affordance on the npc registry row.
    assert render(wizard_view) =~ "Spawn here"

    render_hook(wizard_view, "spawn_here", %{"blueprint_id" => slug})

    flush(witness_view)
    assert render(witness_view) =~ "Mossback the Ogre arrives."

    # A real NPC clone exists in the room, referencing the blueprint, with the
    # toolset's greeting folded into its effective behaviors (FR-016).
    clone = Repo.get_by(NPCClone, blueprint_id: slug)
    refute is_nil(clone)
    assert clone.room_id == Seed.starting_room_id()
    assert Enum.any?(clone.behaviors, &(&1["trigger"] == "player_entered"))
  end

  test "direct-behavior editor: add a behavior alongside a toolset → both commit (FR-015a)",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    name = "warden #{suffix}"

    stub_tool_use("draft_npc_blueprint", %{
      "name" => name,
      "short_description" => "a stern gate warden",
      "long_description" => "A scarred warden in studded leather.",
      "lore" => "You keep the gate and trust no one after dark.",
      "toolsets" => ["greeter"]
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a gate warden"})
    |> render_submit()

    await_wizard_unlock(view)

    # The direct-behavior editor is present and starts empty.
    assert render(view) =~ "Direct behaviors"

    # Add a row, then fill it via the form-change with the toolset preserved.
    render_hook(view, "add_direct_behavior", %{})

    render_hook(view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => name,
        "short_description" => "a stern gate warden",
        "long_description" => "A scarred warden in studded leather.",
        "lore" => "You keep the gate and trust no one after dark.",
        "toolsets" => ["greeter"],
        "behaviors" => %{
          "0" => %{"trigger" => "player_left", "type" => "emote", "text" => "narrows his eyes."}
        }
      }
    })

    render_hook(view, "commit_blueprint_draft", %{})

    slug = name |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    bp = Queries.get_npc_blueprint_row(slug)

    # The blueprint carries BOTH the toolset and the individually-added behavior.
    assert bp.toolsets == ["greeter"]

    assert bp.behaviors == [
             %{
               "trigger" => "player_left",
               "actions" => [%{"type" => "emote", "text" => "narrows his eyes."}]
             }
           ]
  end

  test "extract essence from an in-world NPC → trance + pre-filled npc draft → commit (US6)",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    # World mode: the NPCs-in-this-room panel lists the seeded Garrick.
    html = render(view)
    assert html =~ "NPCs in"
    assert html =~ "Garrick the Innkeeper"

    garrick = Repo.get_by(NPCClone, blueprint_id: "garrick_the_innkeeper")
    render_hook(view, "extract_npc_essence", %{"clone_id" => garrick.id})

    # Flipped into the sanctum with a pre-filled npc draft (lore field present).
    html = render(view)
    assert html =~ "sanctum"
    assert html =~ "Garrick the Innkeeper"
    assert html =~ "Lore"

    # The auto-derived slug collides with the seeded blueprint; rename it.
    new_slug = "garrick_copy_#{suffix}"
    render_hook(view, "update_blueprint_draft", %{"draft" => %{"proposed_slug" => new_slug}})
    render_hook(view, "commit_blueprint_draft", %{})

    bp = Queries.get_npc_blueprint_row(new_slug)
    assert bp.kind == "npc"
    assert bp.revision == 1
    assert bp.name == "Garrick the Innkeeper"
    # The source clone is unchanged (still references its own blueprint).
    assert Repo.get(NPCClone, garrick.id).blueprint_id == "garrick_the_innkeeper"
  end

  test "edit an npc blueprint's lore via the form → revision bump (US7)",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    name = "sage #{suffix}"

    stub_tool_use("draft_npc_blueprint", %{
      "name" => name,
      "short_description" => "a wise sage",
      "long_description" => "An old sage by the fire.",
      "lore" => "v1 lore",
      "toolsets" => []
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a sage"})
    |> render_submit()

    await_wizard_unlock(view)
    render_hook(view, "commit_blueprint_draft", %{})

    slug = name |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    assert Queries.get_npc_blueprint_row(slug).revision == 1

    # Focus the blueprint from the registry → edit form (expected_revision 1).
    render_hook(view, "focus_blueprint", %{"blueprint_id" => slug})
    render_hook(view, "update_blueprint_draft", %{"draft" => %{"lore" => "v2 lore, much wiser"}})
    render_hook(view, "commit_blueprint_draft", %{})

    bp = Queries.get_npc_blueprint_row(slug)
    assert bp.revision == 2
    assert bp.lore == "v2 lore, much wiser"
  end

  test "edit an in-world NPC clone in place; the blueprint is untouched (US7)",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    garrick = Repo.get_by(NPCClone, blueprint_id: "garrick_the_innkeeper")
    render_hook(view, "focus_npc_for_edit", %{"clone_id" => garrick.id})
    assert render(view) =~ "Edit NPC"

    render_hook(view, "update_npc_edit", %{
      "edit" => %{"long_description" => "Now wearing a fresh apron."}
    })

    render_hook(view, "commit_npc_edit", %{})

    assert Repo.get(NPCClone, garrick.id).long_description == "Now wearing a fresh apron."
    # The source blueprint is unchanged (no reverse propagation).
    assert Queries.get_npc_blueprint_row("garrick_the_innkeeper").long_description =~ "wiry man"
  end

  test "unified registry shows both kinds with badges; kind filter narrows it (US8)",
       %{wizard: wizard, wizard_conn: wzc, suffix: suffix} do
    obj_slug = "chest_#{suffix}"
    npc_slug = "ogre_reg_#{suffix}"

    {:ok, ^obj_slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: obj_slug,
        name: "Brass Chest #{suffix}",
        short_description: "a brass chest",
        long_description: "A brass-bound chest."
      })

    {:ok, ^npc_slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: npc_slug,
        name: "Registry Ogre #{suffix}",
        short_description: "an ogre",
        long_description: "An ogre."
      })

    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    # Default :all — both kinds present, each with a kind badge.
    html = render(view)
    assert html =~ "Brass Chest #{suffix}"
    assert html =~ "Registry Ogre #{suffix}"
    assert html =~ ~s(data-testid="blueprint-kind-#{obj_slug}")
    assert html =~ ~s(data-testid="blueprint-kind-#{npc_slug}")

    # Filter → NPCs only.
    render_hook(view, "filter_blueprints", %{"kind" => "npc"})
    html = render(view)
    assert html =~ "Registry Ogre #{suffix}"
    refute html =~ "Brass Chest #{suffix}"

    # Filter → Objects only.
    render_hook(view, "filter_blueprints", %{"kind" => "object"})
    html = render(view)
    assert html =~ "Brass Chest #{suffix}"
    refute html =~ "Registry Ogre #{suffix}"
  end

  # --- Helpers ------------------------------------------------------------

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
  end

  defp flush(view) do
    _ = :sys.get_state(view.pid)
    :ok
  end

  defp stub_tool_use(tool_name, input) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "id" => "toolu_test", "name" => tool_name, "input" => input}
        ],
        "stop_reason" => "tool_use"
      })
    end)
  end

  defp await_wizard_unlock(view, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_wizard_unlock(view, deadline)
  end

  defp do_await_wizard_unlock(view, deadline) do
    state = :sys.get_state(view.pid)

    cond do
      not state.socket.assigns.wizard_input_locked ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("wizard resolver task did not complete (input still locked) within timeout")

      true ->
        Process.sleep(25)
        do_await_wizard_unlock(view, deadline)
    end
  end
end
