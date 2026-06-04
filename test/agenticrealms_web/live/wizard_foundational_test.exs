defmodule AgenticRealmsWeb.WizardFoundationalTest do
  @moduledoc """
  Feature 014 — foundational LiveView smoke tests for wizard authorization
  (FR-WIZ-1 through FR-WIZ-4) and the trance broadcast pipeline (FR-002 /
  FR-003 / FR-004).

  Story-level integration tests for the full authoring loop land alongside
  US1 in `wizard_authoring_test.exs`.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, witness} =
      Accounts.register_player(%{username: "wit_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    starting = Seed.starting_room_id()
    {:ok, _} = Commands.spawn(wizard.id, starting)
    {:ok, _} = Commands.spawn(witness.id, starting)

    %{
      wizard: wizard,
      witness: witness,
      wizard_conn: conn_for(conn, wizard.id),
      witness_conn: conn_for(conn, witness.id)
    }
  end

  test "non-wizard sees no top-bar Wizard switch (FR-WIZ-3) and crafted switch_mode is refused (FR-WIZ-4)",
       %{witness_conn: wc} do
    {:ok, view, html} = live(wc, ~p"/play")

    # FR-WIZ-3 — the top-bar mode switch is hidden for non-wizards.
    refute html =~ ~r/phx-click="switch_mode".*Wizard/s
    refute html =~ ~r/phx-value-mode="wizard"/

    # FR-WIZ-4 — a crafted switch_mode event aiming for :wizard is refused
    # without any visible state change.
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    refute render(view) =~ "Wizard mode · creator"
  end

  test "wizard's authoring mode toggle broadcasts trance log entries to co-present players (FR-002 / FR-003) and is self-suppressed (actor exclusion)",
       %{wizard_conn: wzc, witness_conn: wtc, wizard: wizard} do
    {:ok, wizard_view, _} = live(wzc, ~p"/play")
    {:ok, witness_view, _} = live(wtc, ~p"/play")

    # Enter Wizard view, then flip into Sanctum (blueprint authoring mode).
    render_hook(wizard_view, "switch_mode", %{"mode" => "wizard"})
    render_hook(wizard_view, "toggle_authoring_mode", %{})

    flush(witness_view)
    witness_html = render(witness_view)
    assert witness_html =~ "#{wizard.username} enters a trance."

    # Self-suppression — the wizard's own session does NOT see the entry
    # in their own narrative log (FR-002 wording: "every *other* player
    # session"). The wizard's authoring chrome change is their feedback.
    refute render(wizard_view) =~ "#{wizard.username} enters a trance."

    # Return to World. FR-003 — exit entry fires.
    render_hook(wizard_view, "toggle_authoring_mode", %{})
    flush(witness_view)
    witness_html_after = render(witness_view)
    assert witness_html_after =~ "#{wizard.username} appears to come out of a trance."
    refute render(wizard_view) =~ "#{wizard.username} appears to come out of a trance."
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
