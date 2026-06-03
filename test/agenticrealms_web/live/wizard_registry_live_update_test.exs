defmodule AgenticRealmsWeb.WizardRegistryLiveUpdateTest do
  @moduledoc """
  Feature 014 US6 — global Blueprint registry live-updates: any wizard's
  create/edit shows up in every other wizard's open registry without a
  manual reload.
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

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_#{suffix}", password: "pw12345678"})

    {:ok, bob} =
      Accounts.register_player(%{username: "bob_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(alice.id)
    {:ok, _} = Accounts.promote_to_wizard(bob.id)
    {:ok, _} = Commands.spawn(alice.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(bob.id, Seed.starting_room_id())

    %{
      alice: alice,
      bob: bob,
      alice_conn: conn_for(conn, alice.id),
      bob_conn: conn_for(conn, bob.id),
      suffix: suffix
    }
  end

  test "Alice creates a blueprint → Bob's open registry shows the new row without reload",
       %{alice: alice, alice_conn: ac, bob_conn: bc, suffix: suffix} do
    {:ok, bob_view, _} = live(bc, ~p"/play")
    render_hook(bob_view, "switch_mode", %{"mode" => "wizard"})

    slug = "alice_live_chest_#{suffix}"
    refute render(bob_view) =~ slug

    # Alice authors a blueprint via the wrapper (equivalent of clicking
    # Commit in her own LiveView — same code path the LiveView uses).
    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: alice.id,
        blueprint_id: slug,
        name: "alice's live chest",
        short_description: "a brass-bound live-update chest",
        long_description: "An exhaustively-tested live-update chest."
      })

    wait_for_render(bob_view, slug)
    bob_html = render(bob_view)
    assert bob_html =~ "alice&#39;s live chest"
  end

  test "Alice edits an existing blueprint → Bob's open registry patches the row in place",
       %{alice: alice, alice_conn: ac, bob_conn: bc, suffix: suffix} do
    slug = "alice_edit_chest_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: alice.id,
        blueprint_id: slug,
        name: "pre-edit chest",
        short_description: "a pre-edit chest",
        long_description: "Before any edits land."
      })

    {:ok, bob_view, _} = live(bc, ~p"/play")
    render_hook(bob_view, "switch_mode", %{"mode" => "wizard"})

    assert render(bob_view) =~ "pre-edit chest"

    # Alice edits BOTH the name and the short_description so the
    # assertion below can verify the row was patched in place rather
    # than the unchanged short_description matching the old substring.
    {:ok, 2} =
      Commands.edit_object_blueprint(alice.id, slug, %{
        expected_revision: 1,
        fields_changed: %{
          name: "post-edit chest",
          short_description: "a post-edit chest"
        }
      })

    wait_for_render(bob_view, "post-edit chest")
    bob_html = render(bob_view)
    assert bob_html =~ "a post-edit chest"
    refute bob_html =~ "pre-edit chest"
  end

  test "non-wizards do not see the blueprints registry at all",
       %{bob: bob, conn: conn} do
    # Bob was promoted in setup; demote him for this test by writing
    # is_wizard=false directly via the schema (no Accounts API exists
    # for demotion in milestone 1 — see Q1 clarification: future
    # region-based authz will gate this).
    bob
    |> Ecto.Changeset.change(is_wizard: false)
    |> AgenticRealms.Repo.update!()

    bob_conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:player_id, bob.id)
    {:ok, view, _} = live(bob_conn, ~p"/play")
    refute render(view) =~ "blueprints-registry"
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

  # The UIEventBroadcaster runs at :eventual consistency, so the
  # WizardBlueprintRegistryChanged broadcast lands asynchronously
  # after the Commands wrapper returns. Poll the rendered HTML until
  # the expected substring appears or we time out.
  defp wait_for_render(view, needle, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_render(view, needle, deadline)
  end

  defp do_wait_for_render(view, needle, deadline) do
    if render(view) =~ needle do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk(
          "did not see #{inspect(needle)} within timeout. last render: #{String.slice(render(view), 0, 800)}…"
        )
      else
        Process.sleep(25)
        do_wait_for_render(view, needle, deadline)
      end
    end
  end
end
