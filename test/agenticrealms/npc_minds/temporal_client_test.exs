defmodule AgenticRealms.NpcMinds.TemporalClientTest do
  @moduledoc "The Temporal HTTP client (start/terminate/list), stubbed via Req.Test."
  use ExUnit.Case, async: true

  alias AgenticRealms.NpcMinds.TemporalClient

  @client AgenticRealms.NpcMinds.TemporalClient

  test "start_workflow posts USE_EXISTING with a base64 json payload to npc-<id>" do
    parent = self()

    Req.Test.stub(@client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:req, conn.method, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    assert :ok = TemporalClient.start_workflow("abc-123")

    assert_received {:req, "POST", "/api/v1/namespaces/default/workflows/npc-abc-123", body}
    assert body["workflowType"]["name"] == "NpcWorkflow"
    assert body["taskQueue"]["name"] == "npc-minds"
    assert body["workflowIdConflictPolicy"] == "WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING"
    [payload] = body["input"]["payloads"]
    assert Base.decode64!(payload["data"]) |> Jason.decode!() == %{"entity_id" => "abc-123"}
  end

  test "start_workflow maps a non-2xx to {:error, _} (best-effort)" do
    Req.Test.stub(@client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, "{}")
    end)

    assert {:error, {:http_status, 500}} = TemporalClient.start_workflow("x")
  end

  test "start_workflow maps a transport error to {:error, _}" do
    Req.Test.stub(@client, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, _} = TemporalClient.start_workflow("x")
  end

  test "terminate_workflow posts to .../terminate" do
    parent = self()

    Req.Test.stub(@client, fn conn ->
      send(parent, {:path, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    assert :ok = TemporalClient.terminate_workflow("abc-123")
    assert_received {:path, "/api/v1/namespaces/default/workflows/npc-abc-123/terminate"}
  end

  test "terminate_workflow tolerates a 404 (already gone) as :ok" do
    Req.Test.stub(@client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, "{}")
    end)

    assert :ok = TemporalClient.terminate_workflow("gone")
  end

  test "list_running_npc_ids strips the npc- prefix and ignores non-NPC workflows" do
    Req.Test.stub(@client, fn conn ->
      Req.Test.json(conn, %{
        "executions" => [
          %{"execution" => %{"workflowId" => "npc-a"}},
          %{"execution" => %{"workflowId" => "npc-b"}},
          %{"execution" => %{"workflowId" => "some-other-workflow"}}
        ]
      })
    end)

    assert {:ok, ids} = TemporalClient.list_running_npc_ids()
    assert Enum.sort(ids) == ["a", "b"]
  end
end
