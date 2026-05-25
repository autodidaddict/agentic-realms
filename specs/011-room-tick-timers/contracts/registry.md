# Contract: `AgenticRealms.World.Ticks.Registry` + `AgenticRealms.World.Ticks.Supervisor`

Thin wrappers around `Horde.Registry` and `Horde.DynamicSupervisor` for per-room schedulers. Mirror the pattern established by `AgenticRealms.World.NPCChat.Registry` / `.Supervisor` (feature 010).

## `Registry`

```elixir
defmodule AgenticRealms.World.Ticks.Registry do
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Horde.Registry, :start_link, [[name: __MODULE__, keys: :unique, members: :auto]]},
      type: :supervisor
    }
  end

  @spec via_tuple(room_id :: String.t()) :: {:via, Horde.Registry, {module(), String.t()}}
  def via_tuple(room_id) when is_binary(room_id) do
    {:via, Horde.Registry, {__MODULE__, room_id}}
  end

  @spec lookup(room_id :: String.t()) :: {:ok, pid()} | :error
  def lookup(room_id) do
    case Horde.Registry.lookup(__MODULE__, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
```

## `Supervisor`

```elixir
defmodule AgenticRealms.World.Ticks.Supervisor do
  alias AgenticRealms.World.Ticks.{Registry, Scheduler}

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Horde.DynamicSupervisor, :start_link,
              [[name: __MODULE__,
                strategy: :one_for_one,
                members: :auto,
                distribution_strategy: Horde.UniformDistribution]]},
      type: :supervisor
    }
  end

  @spec find_or_start(room_id :: String.t()) :: {:ok, pid()} | {:error, term()}
  def find_or_start(room_id) when is_binary(room_id) do
    case Registry.lookup(room_id) do
      {:ok, pid} -> {:ok, pid}
      :error ->
        spec = %{
          id: Scheduler,
          start: {Scheduler, :start_link, [room_id]},
          restart: :transient,
          shutdown: 5_000
        }

        case Horde.DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end
end
```

## Test surface

`RegistryTest`:

- `via_tuple/1` returns the expected three-tuple shape.
- `lookup/1` returns `:error` for an unregistered room.
- `lookup/1` returns `{:ok, pid}` after a successful `Supervisor.find_or_start/1`.

`SupervisorTest` (covered partially by `LifecycleTest` and `SchedulerTest`):

- `find_or_start/1` for a fresh room starts a new Scheduler and registers it.
- `find_or_start/1` for an already-started room returns the existing pid (idempotent).
- Calling `find_or_start/1` concurrently from two callers for the same room results in exactly one Scheduler (the second call returns the same pid via the `:already_started` branch).
