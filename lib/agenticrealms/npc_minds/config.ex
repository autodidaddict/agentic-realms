defmodule AgenticRealms.NpcMinds.Config do
  @moduledoc """
  Configuration accessors for the external NPC-mind lifecycle.

  Reads the `:agenticrealms, AgenticRealms.NpcMinds` keyword list (compile-time
  defaults in `config/config.exs`, runtime env in `config/runtime.exs`). The
  shared `service_secret` has no compile-time default — when unset the contract
  API fails closed (`RequireServiceToken` rejects every request).

  The lifecycle constants (workflow type/id scheme, task queue) must match
  those in `agentic-realms-npc`.
  """

  @default_base_url "http://localhost:7243"
  @default_namespace "default"
  @default_task_queue "npc-minds"
  @default_workflow_type "NpcWorkflow"
  @default_reconcile_ms 60_000

  @spec service_secret() :: String.t() | nil
  def service_secret, do: get(:service_secret)

  @spec temporal_base_url() :: String.t()
  def temporal_base_url, do: get(:temporal_base_url) || @default_base_url

  @spec temporal_namespace() :: String.t()
  def temporal_namespace, do: get(:temporal_namespace) || @default_namespace

  @spec temporal_task_queue() :: String.t()
  def temporal_task_queue, do: get(:temporal_task_queue) || @default_task_queue

  @spec temporal_api_key() :: String.t() | nil
  def temporal_api_key, do: get(:temporal_api_key)

  @spec workflow_type() :: String.t()
  def workflow_type, do: get(:npc_workflow_type) || @default_workflow_type

  @spec reconcile_interval_ms() :: pos_integer()
  def reconcile_interval_ms, do: get(:reconcile_interval_ms) || @default_reconcile_ms

  @doc "Deterministic per-NPC Temporal workflow id (`npc-<entity_id>`)."
  @spec workflow_id(String.t()) :: String.t()
  def workflow_id(entity_id) when is_binary(entity_id), do: "npc-" <> entity_id

  @doc "Strip the `npc-` prefix from a workflow id; nil for a non-NPC id."
  @spec entity_id_from_workflow_id(String.t()) :: String.t() | nil
  def entity_id_from_workflow_id("npc-" <> entity_id), do: entity_id
  def entity_id_from_workflow_id(_), do: nil

  @doc "Extra options merged into Req requests (tests inject a `Req.Test` plug)."
  @spec req_options() :: keyword()
  def req_options, do: get(:req_options) || []

  defp get(key), do: Application.get_env(:agenticrealms, AgenticRealms.NpcMinds, [])[key]
end
