defmodule AgenticRealmsWeb.WizardSpawnTest do
  @moduledoc """
  Feature 014 US2 — LiveView integration: wizard clicks "Spawn here"
  on a registry row → co-located player sees the arrival entry → the
  spawned object exists in the room's `world_objects` rows with no
  blueprint_id column.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Seed}
  alias AgenticRealms.World.Schemas.Object

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wzs_#{suffix}", password: "pw12345678"})

    {:ok, witness} =
      Accounts.register_player(%{username: "wit_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(witness.id, Seed.starting_room_id())

    slug = "spawn_chest_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "spawn chest",
        short_description: "a brass-bound spawn chest",
        long_description: "An exhaustively-tested chest with the seal of US2."
      })

    %{
      wizard: wizard,
      witness: witness,
      wizard_conn: conn_for(conn, wizard.id),
      witness_conn: conn_for(conn, witness.id),
      slug: slug
    }
  end

  test "Spawn here → object lands in the room and co-present player sees the arrival entry",
       %{wizard_conn: wzc, witness_conn: wtc, slug: slug} do
    {:ok, wizard_view, _} = live(wzc, ~p"/play")
    {:ok, witness_view, _} = live(wtc, ~p"/play")

    render_hook(wizard_view, "switch_mode", %{"mode" => "wizard"})

    # Registry row's Spawn here button only renders in :world mode.
    html = render(wizard_view)
    assert html =~ "Spawn here"

    render_hook(wizard_view, "spawn_here", %{"blueprint_id" => slug})

    flush(witness_view)
    witness_html = render(witness_view)
    # Arrival entry uses the (constrained, short) name with article,
    # not the long short_description — see lib/agenticrealms_web/live/
    # game_live.ex `object_arrival_text/1`.
    assert witness_html =~ "A spawn chest appears."

    # Wizard's own session shows a transient spawn confirmation toast.
    assert render(wizard_view) =~ "Spawned"

    # The object exists in world_objects, located in the starting room,
    # carrying the blueprint's denormalized payload — and no blueprint_id.
    row =
      Repo.get_by(Object, name: "spawn chest", room_id: Seed.starting_room_id())

    refute is_nil(row)
    refute Map.has_key?(Map.from_struct(row), :blueprint_id)
    assert row.short_description == "a brass-bound spawn chest"
  end

  test "Spawn here is not exposed in :blueprints mode (FR-027)",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    refute render(view) =~ "Spawn here"
  end

  test "Spawn here while a non-wizard is in the same room: action refused for non-wizard",
       %{witness_conn: wtc, slug: slug} do
    {:ok, view, _} = live(wtc, ~p"/play")

    # Non-wizards never see Wizard view to begin with — but a crafted
    # spawn_here event must be refused at the handler entry.
    render_hook(view, "spawn_here", %{"blueprint_id" => slug})

    # No arrival entry generated (handler refused without dispatching).
    refute render(view) =~ "A spawn chest appears."
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
