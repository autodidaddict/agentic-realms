defmodule AgenticRealms.NpcMinds.TemporalClient do
  @moduledoc """
  Feature 018 — thin HTTP client for the **Temporal server's** HTTP API, built on
  `Req`. Starts/terminates one durable workflow per NPC (`npc-<entity_id>`) and
  lists running NPC workflows for the reconciler. This talks to the Temporal
  server, **never** to the `agentic-realms-npc` worker.

  Idempotency and tolerance are Temporal's, not the game's:

    * `start_workflow/1` sends `workflowIdConflictPolicy = USE_EXISTING`, so a
      second start for a running NPC returns the existing run (never two minds).
    * `terminate_workflow/1` maps a not-found workflow to `:ok` (terminating an
      already-stopped/absent mind is a no-op).

  Every failure is mapped to `{:error, reason}` and logged; no exception escapes.
  Callers (the lifecycle handler, the purge, the reconciler) treat this as
  best-effort and never block a world change on it.

  Config: `AgenticRealms.NpcMinds.Config` (base URL, namespace, task queue, API
  key, workflow type). Tests inject a `Req.Test` plug via `:req_options`.
  """

  require Logger

  alias AgenticRealms.NpcMinds.Config

  # base64("json/plain") — Temporal Payload metadata encoding for a JSON value.
  @json_encoding Base.encode64("json/plain")
  @identity "agentic-realms"

  @doc "Start the NPC's mind workflow (idempotent via USE_EXISTING). Best-effort."
  @spec start_workflow(String.t()) :: :ok | {:error, term()}
  def start_workflow(entity_id) when is_binary(entity_id) do
    wf_id = Config.workflow_id(entity_id)

    body = %{
      "workflowType" => %{"name" => Config.workflow_type()},
      "taskQueue" => %{"name" => Config.temporal_task_queue()},
      "input" => %{"payloads" => [json_payload(%{"entity_id" => entity_id})]},
      "workflowIdConflictPolicy" => "WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING",
      "identity" => @identity,
      "requestId" => request_id()
    }

    case request(:post, "/workflows/#{wf_id}", json: body) do
      {:ok, status} when status in 200..299 ->
        :ok

      {:ok, status} ->
        Logger.warning("Temporal start #{wf_id} returned HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Temporal start #{wf_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Terminate the NPC's mind workflow. A not-found workflow is a no-op (`:ok`)."
  @spec terminate_workflow(String.t()) :: :ok | {:error, term()}
  def terminate_workflow(entity_id) when is_binary(entity_id) do
    wf_id = Config.workflow_id(entity_id)
    body = %{"reason" => "npc removed", "identity" => @identity}

    case request(:post, "/workflows/#{wf_id}/terminate", json: body) do
      {:ok, status} when status in 200..299 ->
        :ok

      # Already stopped / never started — tolerated per FR-028.
      {:ok, 404} ->
        :ok

      {:ok, status} ->
        Logger.warning("Temporal terminate #{wf_id} returned HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Temporal terminate #{wf_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Entity ids of currently-running NPC minds (workflow type `NpcWorkflow`, status
  Running), from Temporal visibility. Follows pagination. Used by the reconciler.
  """
  @spec list_running_npc_ids() :: {:ok, [String.t()]} | {:error, term()}
  def list_running_npc_ids do
    query = "WorkflowType = '#{Config.workflow_type()}' AND ExecutionStatus = 'Running'"
    collect_running(query, nil, [])
  end

  # --- internals ----------------------------------------------------------

  defp collect_running(query, page_token, acc) do
    params = [query: query] ++ if(page_token, do: [nextPageToken: page_token], else: [])

    case request(:get, "/workflows", params: params, decode: true) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        ids =
          body
          |> Map.get("executions", [])
          |> Enum.map(fn ex -> get_in(ex, ["execution", "workflowId"]) end)
          |> Enum.map(&Config.entity_id_from_workflow_id/1)
          |> Enum.reject(&is_nil/1)

        case Map.get(body, "nextPageToken") do
          token when is_binary(token) and token != "" ->
            collect_running(query, token, acc ++ ids)

          _ ->
            {:ok, acc ++ ids}
        end

      {:ok, %{status: status}} ->
        Logger.warning("Temporal list returned HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Temporal list failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Perform a Temporal HTTP request. Returns `{:ok, status}` (or `{:ok, %{status,
  # body}}` when `decode: true`) or `{:error, reason}`; never raises.
  defp request(method, path, opts) do
    decode = Keyword.get(opts, :decode, false)

    req_opts =
      [
        method: method,
        url: base() <> path,
        headers: headers(),
        receive_timeout: 5_000,
        retry: false
      ]
      |> maybe_put(:json, Keyword.get(opts, :json))
      |> maybe_put(:params, Keyword.get(opts, :params))
      |> Kernel.++(Config.req_options())

    try do
      case Req.request(req_opts) do
        {:ok, %Req.Response{status: status, body: body}} ->
          if decode, do: {:ok, %{status: status, body: normalize_body(body)}}, else: {:ok, status}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    rescue
      exception -> {:error, {:exception, exception}}
    end
  end

  defp base do
    Config.temporal_base_url() <> "/api/v1/namespaces/" <> Config.temporal_namespace()
  end

  defp headers do
    case Config.temporal_api_key() do
      key when is_binary(key) and key != "" -> [{"authorization", "Bearer " <> key}]
      _ -> []
    end
  end

  defp json_payload(value) do
    %{
      "metadata" => %{"encoding" => @json_encoding},
      "data" => Base.encode64(Jason.encode!(value))
    }
  end

  defp request_id, do: Ecto.UUID.generate()

  defp normalize_body(body) when is_map(body), do: body
  defp normalize_body(body) when is_binary(body), do: Jason.decode!(body)
  defp normalize_body(_), do: %{}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
