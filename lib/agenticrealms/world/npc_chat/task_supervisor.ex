defmodule AgenticRealms.World.NPCChat.TaskSupervisor do
  @moduledoc """
  Task.Supervisor dedicated to NPC-chat LLM round-trips.

  Conversation GenServers spawn LLM-call tasks here (rather than under
  their own supervision) so a slow or crashing Anthropic call cannot
  take down the Conversation that owns the chat history. Tasks send
  their result back to the Conversation via `Process.send/2` and exit.

  Parallel sibling of `AgenticRealms.IntentResolverTaskSupervisor` from
  feature 005 — same role, distinct supervision so a flood in one
  surface doesn't starve the other.
  """

  @doc false
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg) do
    Supervisor.child_spec({Task.Supervisor, name: __MODULE__}, id: __MODULE__)
  end
end
