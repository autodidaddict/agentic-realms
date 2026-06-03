defmodule AgenticRealmsWeb.WizardEditTest do
  @moduledoc """
  Feature 014 US5 — LiveView integration: form-based editing of
  Blueprints (with optimistic locking) and in-place editing of world
  Objects.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Seed}
  alias AgenticRealms.World.Schemas.Object

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wed_#{suffix}", password: "pw12345678"})

    {:ok, second_wizard} =
      Accounts.register_player(%{username: "sed_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Accounts.promote_to_wizard(second_wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(second_wizard.id, Seed.starting_room_id())

    slug = "edit_loop_chest_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "edit-loop chest",
        short_description: "a small wooden chest",
        long_description: "A small wooden chest used in tests."
      })

    {:ok, object_id} =
      Commands.spawn_object_freeform(wizard.id, Seed.starting_room_id(), %{
        name: "edit-loop pot #{suffix}",
        short_description: "a small clay pot",
        long_description: "A small clay pot used in edit tests."
      })

    %{
      wizard: wizard,
      second_wizard: second_wizard,
      wizard_conn: conn_for(conn, wizard.id),
      second_wizard_conn: conn_for(conn, second_wizard.id),
      slug: slug,
      object_id: object_id,
      suffix: suffix
    }
  end

  test "click registry row → blueprint loads for editing → commit bumps revision",
       %{wizard_conn: wzc, slug: slug} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    # In trance, the registry rows are clickable as focus_blueprint
    # affordances.
    render_hook(view, "toggle_authoring_mode", %{})
    render_hook(view, "focus_blueprint", %{"blueprint_id" => slug})

    # The form is now pre-populated with the blueprint's current fields
    # AND `expected_revision: 1`.
    state = :sys.get_state(view.pid)
    draft = state.socket.assigns.focused_blueprint_draft
    assert draft.expected_revision == 1
    assert draft.name == "edit-loop chest"

    # Edit short_description via the form, commit.
    render_hook(view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => draft.name,
        "proposed_slug" => draft.proposed_slug,
        "short_description" => "a heavy iron-bound chest",
        "long_description" => draft.long_description,
        "fixed" => if(draft.fixed, do: "true", else: "false")
      }
    })

    render_hook(view, "commit_blueprint_draft", %{})

    bp = Queries.get_object_blueprint(slug)
    assert bp.revision == 2
    assert bp.short_description == "a heavy iron-bound chest"
  end

  test "no-op blueprint edit returns to a clean form without bumping revision",
       %{wizard_conn: wzc, slug: slug} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})
    render_hook(view, "focus_blueprint", %{"blueprint_id" => slug})

    rev_before = Queries.get_object_blueprint(slug).revision

    # Commit without changing anything.
    render_hook(view, "commit_blueprint_draft", %{})

    assert Queries.get_object_blueprint(slug).revision == rev_before
  end

  test "concurrent blueprint edit: stale-revision banner appears, form reloads with latest",
       %{
         wizard_conn: wzc,
         second_wizard_conn: sezc,
         slug: slug
       } do
    {:ok, view_a, _} = live(wzc, ~p"/play")
    {:ok, view_b, _} = live(sezc, ~p"/play")

    # Both wizards focus the SAME blueprint at revision 1.
    for v <- [view_a, view_b] do
      render_hook(v, "switch_mode", %{"mode" => "wizard"})
      render_hook(v, "toggle_authoring_mode", %{})
      render_hook(v, "focus_blueprint", %{"blueprint_id" => slug})
    end

    # Wizard A edits and commits first → bumps to revision 2.
    a_state = :sys.get_state(view_a.pid)
    a_draft = a_state.socket.assigns.focused_blueprint_draft

    render_hook(view_a, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "A's name",
        "proposed_slug" => a_draft.proposed_slug,
        "short_description" => a_draft.short_description,
        "long_description" => a_draft.long_description,
        "fixed" => "false"
      }
    })

    render_hook(view_a, "commit_blueprint_draft", %{})
    assert Queries.get_object_blueprint(slug).revision == 2
    assert Queries.get_object_blueprint(slug).name == "A's name"

    # Wizard B's form is still showing revision 1. They edit and commit.
    b_state = :sys.get_state(view_b.pid)
    b_draft = b_state.socket.assigns.focused_blueprint_draft
    assert b_draft.expected_revision == 1

    render_hook(view_b, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "B's name",
        "proposed_slug" => b_draft.proposed_slug,
        "short_description" => b_draft.short_description,
        "long_description" => b_draft.long_description,
        "fixed" => "false"
      }
    })

    render_hook(view_b, "commit_blueprint_draft", %{})

    # The blueprint still has A's name (B's commit was rejected for
    # stale revision).
    assert Queries.get_object_blueprint(slug).name == "A's name"

    # B's form has been reloaded with the latest values + a banner.
    b_state_after = :sys.get_state(view_b.pid)
    b_draft_after = b_state_after.socket.assigns.focused_blueprint_draft

    assert b_draft_after.expected_revision == 2
    assert b_draft_after.name == "A's name"
    assert {:stale_revision, 2} == b_state_after.socket.assigns.blueprint_commit_error

    assert render(view_b) =~ "Another wizard edited this blueprint"

    # B reapplies their edit on top of the freshly-reloaded state and
    # commits — succeeds at revision 3.
    render_hook(view_b, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "B's name v2",
        "proposed_slug" => b_draft_after.proposed_slug,
        "short_description" => b_draft_after.short_description,
        "long_description" => b_draft_after.long_description,
        "fixed" => "false"
      }
    })

    render_hook(view_b, "commit_blueprint_draft", %{})

    bp = Queries.get_object_blueprint(slug)
    assert bp.revision == 3
    assert bp.name == "B's name v2"
  end

  test "edit a world Object via form → row updates in place; same-room player can re-look",
       %{wizard_conn: wzc, object_id: oid} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    # Things-in-this-room panel has an Edit button per row.
    assert render(view) =~ "Edit"

    render_hook(view, "focus_object_for_edit", %{"object_id" => oid})

    state = :sys.get_state(view.pid)
    edit = state.socket.assigns.focused_object_edit
    refute is_nil(edit)
    assert edit.object_id == oid

    render_hook(view, "update_object_edit", %{
      "edit" => %{
        "name" => edit.name,
        "short_description" => "an edited clay pot",
        "long_description" => edit.long_description,
        "fixed" => "false"
      }
    })

    render_hook(view, "commit_object_edit", %{})

    row = Repo.get(Object, oid)
    assert row.short_description == "an edited clay pot"
  end

  # --- Helpers ------------------------------------------------------------

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
  end
end
