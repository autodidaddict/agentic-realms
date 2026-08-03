defmodule AgenticRealms.NpcMinds.LifecycleManager do
  @moduledoc """
  The NPC-mind lifecycle "process manager". A named
  `Commanded.Event.Handler` (⇒ a single exclusive cluster-wide subscriber, so
  exactly one node reacts to each event) that starts a Temporal workflow when an
  NPC is spawned and terminates it when the NPC is removed:

    * `EntityCloned{kind: :npc}`  → `TemporalClient.start_workflow/1`
    * `EntityRemoved{kind: :npc}` → `TemporalClient.terminate_workflow/1`

  Every other event is ignored. The handoff is **best-effort**: on a Temporal
  failure the client logs and returns `{:error, _}`, and this handler still
  returns `:ok` so the subscription advances — the reconciler (`Reconciler`) is
  the convergence backstop. The world change is never blocked by this handler.

  This calls the **Temporal server**, never the `agentic-realms-npc` worker.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  alias AgenticRealms.NpcMinds.TemporalClient
  alias AgenticRealms.World.Events.{EntityCloned, EntityRemoved}

  @impl true
  def handle(%EntityCloned{kind: kind, entity_id: id}, _meta) do
    if npc?(kind), do: TemporalClient.start_workflow(id)
    :ok
  end

  def handle(%EntityRemoved{kind: kind, entity_id: id}, _meta) do
    if npc?(kind), do: TemporalClient.terminate_workflow(id)
    :ok
  end

  defp npc?(:npc), do: true
  defp npc?("npc"), do: true
  defp npc?(_), do: false
end
