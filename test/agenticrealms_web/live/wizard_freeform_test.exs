defmodule AgenticRealmsWeb.WizardFreeformTest do
  @moduledoc """
  Feature 014 US3 — LiveView integration: wizard in World mode types a
  prompt describing a one-off Object → mocked LLM extracts fields →
  wizard commits → Object lands in the wizard's current room WITHOUT
  any row added to the Object Blueprint registry. Co-present player
  sees the arrival entry. Spawn-confirmation toast appears for the
  wizard.
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

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wff_#{suffix}", password: "pw12345678"})

    {:ok, witness} =
      Accounts.register_player(%{username: "wit_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    AgenticRealms.DataCase.create_character!(wizard.id, name: wizard.username)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    AgenticRealms.DataCase.create_character!(witness.id, name: witness.username)
    {:ok, _} = Commands.spawn(witness.id, Seed.starting_room_id())

    %{
      wizard: wizard,
      witness: witness,
      wizard_conn: conn_for(conn, wizard.id),
      witness_conn: conn_for(conn, witness.id),
      suffix: suffix
    }
  end

  test "full US3 loop: world-mode prompt → LLM draft → Commit → Object spawns, no blueprint added",
       %{wizard_conn: wzc, witness_conn: wtc, suffix: suffix} do
    {:ok, wizard_view, _} = live(wzc, ~p"/play")
    {:ok, witness_view, _} = live(wtc, ~p"/play")

    render_hook(wizard_view, "switch_mode", %{"mode" => "wizard"})

    # Stub the LLM to return a manifest_object_freeform tool_use.
    name = "freeform pot #{suffix}"

    stub_tool_use("manifest_object_freeform", %{
      "name" => name,
      "short_description" => "a small clay pot",
      "long_description" => "A small clay pot, half-empty of dry barley.",
      "fixed" => false
    })

    blueprint_count_before = length(Queries.list_object_blueprints())

    # Submit the prompt in world mode.
    wizard_view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a clay pot leaning"})
    |> render_submit()

    await_wizard_unlock(wizard_view)

    # The Object Interpreted Data card now shows the LLM-extracted fields.
    html = render(wizard_view)
    assert html =~ "one-off Object"
    assert html =~ name

    # Commit the draft.
    render_hook(wizard_view, "commit_object_draft", %{})

    # Co-located witness sees the arrival entry.
    flush(witness_view)
    witness_html = render(witness_view)
    assert witness_html =~ "A #{name} appears."

    # An Object row exists in the wizard's current room.
    row =
      Repo.get_by(Object,
        name: name,
        container_type: "room",
        container_id: Seed.starting_room_id()
      )

    refute is_nil(row)
    refute Map.has_key?(Map.from_struct(row), :blueprint_id)
    assert row.short_description == "a small clay pot"

    # No Blueprint was added.
    assert length(Queries.list_object_blueprints()) == blueprint_count_before

    # Wizard's chrome shows the spawn confirmation toast.
    assert render(wizard_view) =~ "Spawned"
  end

  test "Discard clears the freeform draft without spawning anything",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    name = "discard pot #{suffix}"

    stub_tool_use("manifest_object_freeform", %{
      "name" => name,
      "short_description" => "a discardable pot",
      "long_description" => "Long enough description to satisfy required checks.",
      "fixed" => false
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "describe a thing"})
    |> render_submit()

    await_wizard_unlock(view)
    assert render(view) =~ name

    render_hook(view, "discard_object_draft", %{})

    html = render(view)
    refute html =~ "one-off Object"
    assert is_nil(Repo.get_by(Object, name: name))
  end

  test "LLM refusal surfaces inline and produces no draft",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    stub_tool_use("refuse", %{"message" => "That's a question, not an object."})

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "what time is it"})
    |> render_submit()

    await_wizard_unlock(view)

    html = render(view)
    assert html =~ "That&#39;s a question"
    refute html =~ "Interpreted data · one-off Object"
  end

  # --- Helpers ------------------------------------------------------------

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
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

  defp flush(view) do
    _ = :sys.get_state(view.pid)
    :ok
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
