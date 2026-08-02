defmodule AgenticRealmsWeb.WizardExtractTest do
  @moduledoc """
  Feature 014 US4 — LiveView integration: wizard clicks "Extract
  essence" on a world Object → mode flips to :blueprints (trance
  entries fire), focused blueprint draft pre-populates with the
  source Object's fields → wizard refines + Commits → new Blueprint
  at revision 1 → source Object UNCHANGED.
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
      Accounts.register_player(%{username: "wxt_#{suffix}", password: "pw12345678"})

    {:ok, witness} =
      Accounts.register_player(%{username: "wit_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    AgenticRealms.DataCase.create_character!(wizard.id, name: wizard.username)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    AgenticRealms.DataCase.create_character!(witness.id, name: witness.username)
    {:ok, _} = Commands.spawn(witness.id, Seed.starting_room_id())

    # A freeform Object the wizard can later extract from.
    {:ok, object_id} =
      Commands.spawn_object_freeform(wizard.id, Seed.starting_room_id(), %{
        name: "extract source pot #{suffix}",
        short_description: "a small clay extract pot",
        long_description: "A small clay pot the wizard intends to extract essence from."
      })

    %{
      wizard: wizard,
      witness: witness,
      wizard_conn: conn_for(conn, wizard.id),
      witness_conn: conn_for(conn, witness.id),
      object_id: object_id,
      suffix: suffix
    }
  end

  test "extract → trance + pre-populated draft → commit → new Blueprint + source untouched",
       %{wizard_conn: wzc, witness_conn: wtc, wizard: wizard, object_id: oid, suffix: suffix} do
    {:ok, wizard_view, _} = live(wzc, ~p"/play")
    {:ok, witness_view, _} = live(wtc, ~p"/play")

    render_hook(wizard_view, "switch_mode", %{"mode" => "wizard"})

    # The Things-in-this-room panel shows the source Object with an
    # Extract essence button.
    html = render(wizard_view)
    assert html =~ "extract source pot"
    assert html =~ "Extract essence"

    # Snapshot the source row before extraction.
    before_row = Repo.get(Object, oid)

    # Click Extract essence — flips to :blueprints, populates the
    # focused blueprint draft with the source object's fields.
    render_hook(wizard_view, "extract_essence", %{"object_id" => oid})

    # Witness sees the trance entry (FR-002 fired by WizardTrance.enter).
    flush(witness_view)
    assert render(witness_view) =~ "#{wizard.username} enters a trance."

    # The wizard chrome now shows the Interpreted Data card pre-populated
    # with the source object's fields.
    wizard_html = render(wizard_view)
    assert wizard_html =~ "Interpreted data"
    assert wizard_html =~ "extract source pot"
    assert wizard_html =~ "a small clay extract pot"

    # Refine the slug to something predictable, then commit.
    expected_slug = "extracted_pot_#{suffix}"

    # The form is bound to `update_blueprint_draft` (phx-change). Push a
    # form-change to override the auto-derived slug, then commit.
    state = :sys.get_state(wizard_view.pid)
    draft = state.socket.assigns.focused_blueprint_draft

    render_hook(wizard_view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => draft.name,
        "proposed_slug" => expected_slug,
        "short_description" => draft.short_description,
        "long_description" => draft.long_description,
        "fixed" => if(draft.fixed, do: "true", else: "false")
      }
    })

    render_hook(wizard_view, "commit_blueprint_draft", %{})

    # Blueprint persisted at revision 1.
    bp = Queries.get_object_blueprint(expected_slug)
    refute is_nil(bp)
    assert bp.revision == 1
    assert bp.name == before_row.name
    assert bp.short_description == before_row.short_description
    assert bp.long_description == before_row.long_description
    assert bp.fixed == before_row.fixed

    # Source Object UNCHANGED.
    after_row = Repo.get(Object, oid)
    assert before_row.name == after_row.name
    assert before_row.short_description == after_row.short_description
    assert before_row.long_description == after_row.long_description
    assert before_row.fixed == after_row.fixed
    assert before_row.container_type == after_row.container_type
    assert before_row.container_id == after_row.container_id
  end

  test "extract while in :blueprints mode is refused (only available in :world mode)",
       %{wizard_conn: wzc, object_id: oid} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    # In trance, the room-objects panel isn't shown and the extract
    # handler refuses if pushed manually.
    refute render(view) =~ "Extract essence"

    state_before = :sys.get_state(view.pid)
    render_hook(view, "extract_essence", %{"object_id" => oid})
    state_after = :sys.get_state(view.pid)

    # No focused draft and no mode change (still :blueprints).
    assert state_after.socket.assigns.authoring_mode == state_before.socket.assigns.authoring_mode
    assert is_nil(state_after.socket.assigns.focused_blueprint_draft)
  end

  test "extract with unknown object_id surfaces an inline error",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    bogus = Ecto.UUID.generate()
    render_hook(view, "extract_essence", %{"object_id" => bogus})

    assert render(view) =~ "That object no longer exists."
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
end
