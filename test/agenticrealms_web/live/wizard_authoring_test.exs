defmodule AgenticRealmsWeb.WizardAuthoringTest do
  @moduledoc """
  Full LiveView integration test for the wizard
  authoring loop: trance toggle → LLM-extracted draft → form refinement
  → Commit → registry shows the new blueprint at revision 1.

  Tagged `:integration` and excluded from the default `mix test` run.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Queries, Seed}

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    AgenticRealms.DataCase.create_character!(wizard.id, name: wizard.username)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())

    wizard_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, wizard.id)

    %{wizard: wizard, wizard_conn: wizard_conn, suffix: suffix}
  end

  test "full US1 loop: trance → prompt → LLM draft → Commit → registry",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _html} = live(wzc, ~p"/play")

    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    render_hook(view, "toggle_authoring_mode", %{})

    html = render(view)
    assert html =~ "In the"
    assert html =~ "sanctum"
    assert html =~ "Describe an object archetype"

    name = "brass-bound chest #{suffix}"

    stub_tool_use("draft_object_blueprint", %{
      "name" => name,
      "short_description" => "a brass-bound chest",
      "long_description" => "A weather-beaten chest carved with the seal of the Western Reach.",
      "fixed" => true
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a brass chest"})
    |> render_submit()

    await_wizard_unlock(view)

    html = render(view)
    assert html =~ name
    assert html =~ "a brass-bound chest"

    render_hook(view, "commit_blueprint_draft", %{})

    expected_slug = String.replace(name, ~r/[^a-z0-9]+/, "_") |> String.trim("_")
    assert %{revision: 1} = Queries.get_object_blueprint(expected_slug)

    html = render(view)
    assert html =~ name

    refute html =~ "Discard"
  end

  test "Discard clears the draft without persisting and keeps the wizard in trance",
       %{wizard_conn: wzc} do
    {:ok, view, _html} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    stub_tool_use("draft_object_blueprint", %{
      "name" => "discardable",
      "short_description" => "a discardable thing",
      "long_description" => "Long enough description to satisfy the not-blank checks.",
      "fixed" => false
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "describe a thing"})
    |> render_submit()

    await_wizard_unlock(view)
    assert render(view) =~ "discardable"

    render_hook(view, "discard_blueprint_draft", %{})

    html = render(view)
    refute html =~ "discardable"
    assert html =~ "Return to your body"
    assert Queries.get_object_blueprint("discardable") == nil
  end

  test "LLM refusal surfaces inline and does not produce a draft",
       %{wizard_conn: wzc} do
    {:ok, view, _html} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    stub_tool_use("refuse", %{"message" => "That's a question, not an archetype."})

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "what time is it"})
    |> render_submit()

    await_wizard_unlock(view)
    html = render(view)
    assert html =~ "That&#39;s a question"
    refute html =~ "Interpreted data"
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
