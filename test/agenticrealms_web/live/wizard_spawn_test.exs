defmodule AgenticRealmsWeb.WizardSpawnTest do
  @moduledoc """
  LiveView integration: wizard clicks "Spawn here"
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
    AgenticRealms.DataCase.create_character!(wizard.id, name: wizard.username)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    AgenticRealms.DataCase.create_character!(witness.id, name: witness.username)
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

    html = render(wizard_view)
    assert html =~ "Spawn here"

    render_hook(wizard_view, "spawn_here", %{"blueprint_id" => slug})

    assert_eventually(witness_view, fn -> render(witness_view) =~ "A spawn chest appears." end,
      label: "witness saw the object arrive",
      on_timeout: fn -> render(witness_view) end
    )

    assert render(wizard_view) =~ "Spawned"

    row =
      Repo.get_by(Object,
        name: "spawn chest",
        container_type: "room",
        container_id: Seed.starting_room_id()
      )

    refute is_nil(row)
    refute Map.has_key?(Map.from_struct(row), :blueprint_id)
    assert row.short_description == "a brass-bound spawn chest"
  end

  test "Spawn here is not exposed in :blueprints mode",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    refute render(view) =~ "Spawn here"
  end

  test "Spawn here while a non-wizard is in the same room: action refused for non-wizard",
       %{witness_conn: wtc, slug: slug} do
    {:ok, view, _} = live(wtc, ~p"/play")

    render_hook(view, "spawn_here", %{"blueprint_id" => slug})

    refute render(view) =~ "A spawn chest appears."
  end

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
  end
end
