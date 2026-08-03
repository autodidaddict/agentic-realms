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
  to satisfy the NOT NULL FK.
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

  @doc """
  The character columns a `player_state` row carries once `CharacterCreated`
  has been projected, as a keyword list.

  Feature 020 removed the schema's placeholder stat defaults, so a row built
  straight from `%PlayerState{}` has no character and renders nothing. Tests
  that only need *a* character — examine, presence, the sheet — should splat
  this into their insert rather than restating the default Human Fighter:

      Repo.insert!(struct!(PlayerState,
        [player_id: p.id, current_room_id: room_id] ++ DataCase.character_columns()))

  Pass overrides to vary one thing, e.g. `character_columns(level: 5)`.
  """
  def character_columns(overrides \\ []) do
    character = AgenticRealms.World.CharacterGen.default()

    defaults = [
      character_name: character.character_name,
      species_slug: character.species_slug,
      lineage_slug: character.lineage_slug,
      choices: character.choices,
      class_slug: character.class_slug,
      background_slug: character.background_slug,
      size: character.size,
      str: character.abilities.str,
      dex: character.abilities.dex,
      con: character.abilities.con,
      int: character.abilities.int,
      wis: character.abilities.wis,
      cha: character.abilities.cha,
      level: 1,
      xp: 0,
      hp: character.max_hp,
      max_hp: character.max_hp,
      skill_proficiencies: character.skill_proficiencies,
      save_proficiencies: character.save_proficiencies,
      feat_slugs: character.feat_slugs
    ]

    Keyword.merge(defaults, overrides)
  end

  @doc """
  Give a player a character through the real creation path.

  Needed by any test that mounts `/play`: a player with no character now gets
  the creation dialog rather than the world, which is the point of the feature.
  Requires Commanded, so tag the test `:commanded`.

  Pass a name to make a player addressable by it, and any of `:species`,
  `:class`, or `:background` to vary the character.
  """
  def create_character!(player_id, opts \\ []) do
    alias AgenticRealms.World.CharacterDraft, as: Draft

    name = Keyword.get(opts, :name, "Hero#{player_id}")

    draft =
      Draft.new()
      |> Draft.put_name(name)
      |> Draft.put_selection(:species, Keyword.get(opts, :species, "human"))
      |> Draft.put_selection(:class, Keyword.get(opts, :class, "fighter"))
      |> Draft.put_selection(:background, Keyword.get(opts, :background, "soldier"))

    case AgenticRealms.World.PlayerNames.get(player_id) do
      existing when is_binary(existing) ->
        existing

      nil ->
        {:ok, :created} = AgenticRealms.World.Commands.create_character(player_id, draft)
        name
    end
  end

  setup tags do
    AgenticRealms.DataCase.setup_sandbox(tags)
    if tags[:commanded], do: AgenticRealms.DataCase.setup_commanded()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.

  Background tasks are drained before the owner is stopped. See
  `await_background_tasks/1` for why.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AgenticRealms.Repo, shared: not tags[:async])

    on_exit(fn ->
      stop_tick_schedulers()
      await_background_tasks()
      await_lifecycle_idle()
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)
  end

  @doc """
  Wait until `Ticks.Lifecycle` has finished whatever it was doing.

  Lifecycle is the one process in this family that cannot be stopped at
  teardown — schedulers and tasks belong to a test and are disposable, and
  Lifecycle is meant to run forever. It also queries on every presence change,
  so a test that ends while it is resolving a presence diff leaves it holding
  that test's connection. `safe_db/2` means it survives losing the connection,
  but the connection is torn down all the same.

  A `call` is the whole fix: it returns only once Lifecycle has processed
  everything queued ahead of it, so it cannot be mid-query when the owner
  stops. This narrows the window rather than removing it — a presence diff
  arriving between this call and `stop_owner/1` would still land badly — but
  that window is microseconds against the length of a test.

  Only `async: false` tests can hit this at all. An async test owns its
  connection rather than sharing it, so Lifecycle has nothing to borrow and
  its queries fail immediately instead of holding anything.
  """
  def await_lifecycle_idle(timeout \\ 5_000) do
    lifecycle = AgenticRealms.World.Ticks.Lifecycle

    if Process.whereis(lifecycle) do
      GenServer.call(lifecycle, :get_state, timeout)
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Stop any room-tick schedulers this test caused to start.

  A `Ticks.Scheduler` is started by `Ticks.Lifecycle` when a room becomes
  occupied, and it lives under a Horde dynamic supervisor that is not torn down
  between tests. So it outlives the test that started it and keeps querying —
  `Scope.compute/1` on every refresh, the beat timer forever — against a
  sandbox connection borrowed from an owner that is gone. That tears the
  connection down, and the next test to pick it up fails in setup for reasons
  that have nothing to do with it.

  This is the same failure as the background tasks above, one layer up: a
  supervised GenServer rather than a `Task`, which is why draining task
  supervisors did not catch it. A nightly seed run found it as
  `CharacterCreationTest` dying inside `Seed.run/0`.
  """
  def stop_tick_schedulers do
    supervisor = AgenticRealms.World.Ticks.Supervisor

    if Process.whereis(supervisor) do
      for {_, child, _, _} <- Horde.DynamicSupervisor.which_children(supervisor),
          is_pid(child) do
        Horde.DynamicSupervisor.terminate_child(supervisor, child)
      end
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  @background_task_supervisors [
    AgenticRealms.World.NPCChat.TaskSupervisor,
    AgenticRealms.IntentResolverTaskSupervisor
  ]

  @doc """
  Wait for Repo-touching background tasks to finish before the sandbox owner
  is stopped.

  `NPCChat.Conversation` and the intent resolver reply to their caller
  immediately and do the real work in a `Task.Supervisor.async_nolink` task.
  That task reaches the Repo through the sandbox — shared mode for a sync
  test, `$callers` for an async one — so it is borrowing the connection this
  test owns. A test that returns without waiting for the reply leaves the task
  running, `stop_owner/1` then pulls the connection out from under it, and the
  pooled connection is torn down mid-query.

  The test that caused this does not fail. Some *other* test holding that
  connection does, with an error naming a process it has never heard of. It is
  timing-dependent, so it needs pool contention to show up at all — a nightly
  seed run caught it failing `WizardSpawnTest` in setup, seeding rooms, while
  the real culprit was an NPC chat task two files away.

  Waiting here fixes every such test at once, including ones not yet written,
  which is the point: the alternative is remembering to await the reply in
  each test that sends a message.

  Best-effort — a task that will not finish inside `timeout` is left alone
  rather than hanging the suite.
  """
  def await_background_tasks(timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    Enum.each(@background_task_supervisors, &await_supervisor(&1, deadline))
  end

  defp await_supervisor(supervisor, deadline) do
    case children(supervisor) do
      [] ->
        :ok

      pids ->
        Enum.each(pids, &await_exit(&1, deadline))

        if System.monotonic_time(:millisecond) < deadline do
          await_supervisor(supervisor, deadline)
        end
    end
  end

  defp children(supervisor) do
    if Process.whereis(supervisor), do: Task.Supervisor.children(supervisor), else: []
  catch
    :exit, _ -> []
  end

  defp await_exit(pid, deadline) do
    ref = Process.monitor(pid)
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      remaining -> Process.demonitor(ref, [:flush])
    end
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
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.QuestProjector)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Progression.XpAwarder)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.BlueprintProjector)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Projections.EntityProjector)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.UIEventBroadcaster)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Behaviors.Interpreter)
    ExUnit.Callbacks.start_supervised!(AgenticRealms.World.Transient.Registry)
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
