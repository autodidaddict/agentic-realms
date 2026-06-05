defmodule AgenticRealmsWeb.WizardReviewCleanupTest do
  @moduledoc """
  Coverage for the four nit-severity findings from the PR #30
  ultrareview that don't have a natural home in the per-story tests:

    * bug_005 — friendly copy for previously-fallthrough error atoms.
    * bug_006 — slug auto-derive recovers after customize→clear→rename.
    * bug_007 — orphan draft from mode-toggled resolver task is dropped.
    * bug_009 — `:object_blueprints` assign stays homogeneous (all
      `%Blueprint{}` structs) after a cross-wizard broadcast.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}
  alias AgenticRealms.World.Schemas.Blueprint, as: ObjectBlueprintSchema

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wclean_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())

    %{
      wizard: wizard,
      wizard_conn: conn_for(conn, wizard.id),
      suffix: suffix
    }
  end

  test "bug_005 — error atoms render as friendly copy, never as raw inspect",
       %{wizard_conn: wzc} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})

    # Trigger :unknown_object via a crafted focus_object_for_edit with
    # a bogus id. The handler sets :blueprint_commit_error to
    # :unknown_object; rendering must use the friendly clause.
    bogus = Ecto.UUID.generate()
    render_hook(view, "focus_object_for_edit", %{"object_id" => bogus})

    html = render(view)
    assert html =~ "That object no longer exists."
    refute html =~ "Refused: :"
    refute html =~ ":unknown_object"
  end

  test "bug_006 — customize → clear → rename sequence re-derives the slug",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    # Manually populate a draft via the resolver's success path —
    # we inject by dispatching a fake task result through the LiveView's
    # state. Simpler: stub the LLM to return a draft, submit a prompt.
    stub_tool_use("draft_object_blueprint", %{
      "name" => "chest_#{suffix}",
      "short_description" => "a small chest",
      "long_description" => "A small chest for the slug-derivation test.",
      "fixed" => false
    })

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "a chest"})
    |> render_submit()

    await_wizard_unlock(view)

    # Auto-derived slug.
    state = :sys.get_state(view.pid)
    initial_slug = state.socket.assigns.focused_blueprint_draft.proposed_slug
    assert initial_slug == "chest_#{suffix}"

    # 1. Customize the slug.
    render_hook(view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "chest_#{suffix}",
        "proposed_slug" => "iron_chest_v1_#{suffix}",
        "short_description" => "a small chest",
        "long_description" => "A small chest for the slug-derivation test.",
        "fixed" => "false"
      }
    })

    customized = :sys.get_state(view.pid).socket.assigns.focused_blueprint_draft.proposed_slug
    assert customized == "iron_chest_v1_#{suffix}"

    # 2. Clear the slug input — should re-derive from name.
    render_hook(view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "chest_#{suffix}",
        "proposed_slug" => "",
        "short_description" => "a small chest",
        "long_description" => "A small chest for the slug-derivation test.",
        "fixed" => "false"
      }
    })

    cleared = :sys.get_state(view.pid).socket.assigns.focused_blueprint_draft.proposed_slug
    assert cleared == "chest_#{suffix}"

    # 3. Rename — slug MUST re-derive from the new name (the old sticky
    # flag would have kept it pinned to "chest_<suffix>").
    render_hook(view, "update_blueprint_draft", %{
      "draft" => %{
        "name" => "iron chest #{suffix}",
        "proposed_slug" => "",
        "short_description" => "a small chest",
        "long_description" => "A small chest for the slug-derivation test.",
        "fixed" => "false"
      }
    })

    renamed = :sys.get_state(view.pid).socket.assigns.focused_blueprint_draft.proposed_slug
    assert renamed == "iron_chest_#{suffix}"
  end

  test "bug_007 — mode toggle during in-flight resolver task drops the orphan draft",
       %{wizard_conn: wzc, suffix: suffix} do
    {:ok, view, _} = live(wzc, ~p"/play")
    render_hook(view, "switch_mode", %{"mode" => "wizard"})
    render_hook(view, "toggle_authoring_mode", %{})

    # Stub the LLM with a brief sleep so the wizard can toggle modes
    # between submit and completion. The stub runs inside the
    # IntentResolver Task — sleeping there doesn't block the LiveView,
    # so render_hook("toggle_authoring_mode") gets through before the
    # task result arrives.
    stub_tool_use_delayed(
      "draft_object_blueprint",
      %{
        "name" => "orphan_#{suffix}",
        "short_description" => "an orphan draft",
        "long_description" => "Should be dropped after mode flip.",
        "fixed" => false
      },
      400
    )

    view
    |> form("form[phx-submit='submit_wizard_prompt']", %{"text" => "describe a thing"})
    |> render_submit()

    # Toggle modes IMMEDIATELY — the resolver task is still sleeping
    # inside the stub. The render_hook returns synchronously after
    # the toggle handler runs.
    render_hook(view, "toggle_authoring_mode", %{})

    # Authoring mode is :world now; the task is still running in
    # :blueprints mode. Drain the task message.
    await_wizard_unlock(view)

    assigns = :sys.get_state(view.pid).socket.assigns

    assert is_nil(assigns.focused_blueprint_draft),
           "orphan blueprint draft from a mode-toggled task should be dropped"

    refute render(view) =~ "orphan_#{suffix}"
  end

  test "bug_009 — cross-wizard :created broadcast keeps :object_blueprints homogeneous (all structs)",
       %{wizard: alice, suffix: suffix} do
    {:ok, bob} =
      Accounts.register_player(%{username: "bobclean_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(bob.id)
    {:ok, _} = Commands.spawn(bob.id, Seed.starting_room_id())

    # Sign Bob in first; assign starts as a list of structs from the
    # initial Queries.list_object_blueprints/0.
    bob_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, bob.id)

    {:ok, bob_view, _} = live(bob_conn, ~p"/play")
    render_hook(bob_view, "switch_mode", %{"mode" => "wizard"})

    # Verify Bob's initial list is all structs.
    initial = :sys.get_state(bob_view.pid).socket.assigns.object_blueprints

    assert Enum.all?(initial, &is_struct(&1, ObjectBlueprintSchema)),
           "expected initial :object_blueprints to be all Blueprint structs"

    # Alice authors a blueprint; Bob's broadcast handler patches.
    slug = "homogeneous_chest_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: alice.id,
        blueprint_id: slug,
        name: "homogeneous chest",
        short_description: "a struct-shaped chest",
        long_description: "A chest used to test broadcast-row shape."
      })

    wait_for_render(bob_view, slug)

    patched = :sys.get_state(bob_view.pid).socket.assigns.object_blueprints

    assert Enum.all?(patched, &is_struct(&1, ObjectBlueprintSchema)),
           "after a cross-wizard broadcast, :object_blueprints should remain " <>
             "homogeneous structs (bug_009)"

    # And the inserted row is findable via struct-pattern-match.
    expected_slug = slug

    assert Enum.find(patched, fn
             %ObjectBlueprintSchema{id: ^expected_slug} -> true
             _ -> false
           end),
           "broadcast-inserted row should be a struct pattern-matchable on its id"
  end

  # --- Helpers ------------------------------------------------------------

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
  end

  defp stub_tool_use(tool_name, input), do: stub_tool_use_delayed(tool_name, input, 0)

  defp stub_tool_use_delayed(tool_name, input, delay_ms) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      if delay_ms > 0, do: Process.sleep(delay_ms)

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

  defp wait_for_render(view, needle, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_render(view, needle, deadline)
  end

  defp do_wait_for_render(view, needle, deadline) do
    if render(view) =~ needle do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("did not see #{inspect(needle)} within timeout")
      else
        Process.sleep(25)
        do_wait_for_render(view, needle, deadline)
      end
    end
  end
end
