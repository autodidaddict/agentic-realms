defmodule AgenticRealms.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AgenticRealms.DataCase, async: true`, although
  this option is not recommended for other databases.

  ## Per-test Commanded isolation (`@moduletag :commanded`)

  Tests that dispatch commands, exercise projectors, or depend on
  `UIEventBroadcaster` / `Behaviors.Interpreter` MUST be tagged with
  `@moduletag :commanded` (or per-test `@tag :commanded`). The setup
  callback then `start_supervised!`s the full Commanded chain — the
  `World.Application`, the in-memory event store it brings up, both
  projectors, and the broadcast/behavior handlers — so each test gets a
  fresh event store and fresh subscription positions. See issue #10.

  Untagged tests do NOT get Commanded running; they can only exercise
  pure functions (aggregate `execute/2`, projector `handle/2` calls,
  PubSub broadcasts that bypass Commanded, etc.). Trying to dispatch a
  command from an untagged test will fail because `World.Application`
  isn't running.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias AgenticRealms.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AgenticRealms.DataCase
    end
  end

  @doc """
  Insert a Region row for tests that need a Region FK target. Uses a
  unique name per call to avoid collisions across concurrent tests in
  the same sandbox.

  Returns the Region's id (binary_id string).

  Tests that build Room rows directly via `Repo.insert!(%Room{...})`
  should pass `region_id: AgenticRealms.DataCase.insert_test_region()`
  to satisfy the NOT NULL FK introduced in feature 012.
  """
  def insert_test_region(name_prefix \\ "TestRegion") do
    alias AgenticRealms.Repo
    alias AgenticRealms.World.Schemas.Region

    {:ok, region} =
      Repo.insert(%Region{
        id: Ecto.UUID.generate(),
        name: "#{name_prefix}-#{System.unique_integer([:positive])}"
      })

    region.id
  end

  setup tags do
    AgenticRealms.DataCase.setup_sandbox(tags)
    if tags[:commanded], do: AgenticRealms.DataCase.setup_commanded()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AgenticRealms.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Start a fresh Commanded chain under the calling test's supervisor.

  Brings up the `World.Application` (which transitively starts the
  in-memory event store), the read-model projectors, and the broadcast
  and behavior event handlers. `start_supervised!/1` registers each
  child with the ExUnit test process, so the entire chain is torn down
  when the test ends — including the event store's events table and
  the handlers' subscription positions. Issue #10.

  Triggered automatically when a test is tagged `:commanded`. Tests
  using `AgenticRealmsWeb.ConnCase` inherit the same behavior because
  `ConnCase.setup` delegates to `DataCase.setup_sandbox/1` and the
  same `setup tags do ... end` callback above.
  """
  def setup_commanded do
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Application)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.WorldProjector)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.PlayerStateProjector)
    # Feature 013 — Quests. Handles the four finalize-side events. Must
    # be supervised in tests too, otherwise QuestCompleted never lands.
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.QuestProjector)
    # Feature 015 — unified Blueprint projector. Required by any test that
    # dispatches `CreateBlueprint`/`EditBlueprint`, because the wrapper uses
    # `:strong` consistency and waits for this projector to acknowledge.
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.BlueprintProjector)
    # Feature 016 — entity lifecycle projector (world_objects writes).
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.EntityProjector)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.UIEventBroadcaster)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Behaviors.Interpreter)
    # Feature 017 — transient-region reaper. Idle for non-transient tests (its
    # periodic sweep fires only after the production interval); transient tests
    # drive it synchronously via `Transient.Manager.sweep_now/0`.
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Transient.Manager)
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
