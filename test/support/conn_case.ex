defmodule AgenticRealmsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AgenticRealmsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint AgenticRealmsWeb.Endpoint

      use AgenticRealmsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AgenticRealmsWeb.ConnCase
    end
  end

  setup tags do
    AgenticRealms.DataCase.setup_sandbox(tags)
    if tags[:commanded], do: AgenticRealms.DataCase.setup_commanded()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Poll `check.()` against a `Phoenix.LiveViewTest` view until it returns
  truthy or the timeout elapses; flunks otherwise.

  Each poll first drains the LiveView's mailbox via `:sys.get_state/1`
  so any queued PubSub messages (e.g. from `UIEventBroadcaster`, which
  runs with `consistency: :eventual` per issue #9) have been processed
  before the predicate fires. Returns `:ok` on success.

  Options:
    * `:timeout` — total wait in ms (default 1_000)
    * `:label` — short string included in the flunk message
    * `:on_timeout` — zero-arg fn returning extra diagnostic info to
      include in the flunk message (e.g. `fn -> render(view) end`)
  """
  def assert_eventually(view, check, opts \\ []) when is_function(check, 0) do
    timeout_ms = Keyword.get(opts, :timeout, 1_000)
    label = Keyword.get(opts, :label, "predicate")
    on_timeout = Keyword.get(opts, :on_timeout, fn -> nil end)

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_assert_eventually(view, check, deadline, label, timeout_ms, on_timeout)
  end

  defp do_assert_eventually(view, check, deadline, label, timeout_ms, on_timeout) do
    _ = :sys.get_state(view.pid)

    cond do
      check.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        extra =
          case on_timeout.() do
            nil -> ""
            other -> "\nDiagnostic:\n" <> inspect(other, limit: :infinity, pretty: true)
          end

        ExUnit.Assertions.flunk("#{label} did not become true within #{timeout_ms}ms" <> extra)

      true ->
        Process.sleep(20)
        do_assert_eventually(view, check, deadline, label, timeout_ms, on_timeout)
    end
  end
end
