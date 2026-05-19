defmodule AgenticRealms.AnthropicTest do
  @moduledoc """
  Unit tests for the Anthropic HTTP client. Uses `Req.Test` stubs (configured
  in `config/test.exs`) so no request leaves the BEAM. Covers the request
  shape, required headers, and the mapping of every failure mode to
  `{:error, _}`.
  """
  use ExUnit.Case, async: false

  alias AgenticRealms.Anthropic

  @stub AgenticRealms.Anthropic

  test "attaches the x-api-key and anthropic-version headers" do
    Req.Test.stub(@stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key-not-real"]
      assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]
      Req.Test.json(conn, %{"content" => []})
    end)

    assert {:ok, _} = Anthropic.create_message(%{"messages" => []})
  end

  test "injects the configured model into the request body" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["model"] == "claude-haiku-4-5-20251001"
      assert decoded["max_tokens"] == 256
      Req.Test.json(conn, %{"content" => []})
    end)

    assert {:ok, _} =
             Anthropic.create_message(%{"max_tokens" => 256, "messages" => []})
  end

  test "returns {:ok, body} for a 2xx JSON response" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "hi"}]})
    end)

    assert {:ok, %{"content" => [%{"text" => "hi"}]}} =
             Anthropic.create_message(%{"messages" => []})
  end

  test "maps a 4xx response to {:error, {:http_status, status}}" do
    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.send_resp(conn, 400, ~s({"error":"bad request"}))
    end)

    assert {:error, {:http_status, 400}} = Anthropic.create_message(%{"messages" => []})
  end

  test "maps a 5xx response to {:error, {:http_status, status}}" do
    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.send_resp(conn, 529, ~s({"error":"overloaded"}))
    end)

    assert {:error, {:http_status, 529}} = Anthropic.create_message(%{"messages" => []})
  end

  test "maps a transport error to {:error, {:transport, _}}" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, {:transport, _}} = Anthropic.create_message(%{"messages" => []})
  end

  test "maps a non-JSON 200 body to {:error, :malformed_response}" do
    Req.Test.stub(@stub, fn conn ->
      # Plain-text body — Req won't decode it to a map.
      Plug.Conn.send_resp(conn, 200, "this is not json")
    end)

    assert {:error, :malformed_response} = Anthropic.create_message(%{"messages" => []})
  end

  test "returns {:error, :no_api_key} when the API key is absent" do
    original = Application.get_env(:agenticrealms, AgenticRealms.Anthropic)

    on_exit(fn ->
      Application.put_env(:agenticrealms, AgenticRealms.Anthropic, original)
    end)

    Application.put_env(
      :agenticrealms,
      AgenticRealms.Anthropic,
      Keyword.put(original, :api_key, nil)
    )

    assert {:error, :no_api_key} = Anthropic.create_message(%{"messages" => []})
  end
end
