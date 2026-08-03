defmodule AgenticRealms.Anthropic do
  @moduledoc """
  Thin HTTP client for the Anthropic Messages API, built on `Req`.

  Encapsulates the auth header, API version, base URL, model selection, and
  the receive timeout. Every failure mode — missing API key, HTTP error,
  network failure, malformed body — is mapped to `{:error, reason}`; no
  exception escapes `create_message/1`.

  Configuration is read from `Application.get_env(:agenticrealms,
  AgenticRealms.Anthropic)`:

    * `:api_key`     — required at request time; absence → `{:error, :no_api_key}`
    * `:base_url`    — defaults to `https://api.anthropic.com`
    * `:model`      — defaults to `claude-haiku-4-5-20251001`
    * `:timeout_ms` — receive timeout, defaults to 5000
    * `:req_options` — extra options merged into the Req request (tests inject
      a `Req.Test` plug here so no request leaves the BEAM)

  See `specs/005-llm-intent-parser/contracts/intent_resolver_api.md`.
  """

  require Logger

  @anthropic_version "2023-06-01"
  @default_base_url "https://api.anthropic.com"
  @default_model "claude-haiku-4-5-20251001"
  @default_timeout_ms 5_000

  @doc """
  POST a request to `/v1/messages`.

  `payload` is the request body WITHOUT the `model` field — this function
  injects the configured model. Returns `{:ok, response_body_map}` on a
  2xx response, or `{:error, reason}` for every other outcome.
  """
  @spec create_message(map()) :: {:ok, map()} | {:error, term()}
  def create_message(payload) when is_map(payload) do
    config = config()

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        do_request(key, config, payload)

      _ ->
        {:error, :no_api_key}
    end
  end

  defp do_request(api_key, config, payload) do
    base_url = Keyword.get(config, :base_url) || @default_base_url
    model = Keyword.get(config, :model) || @default_model
    timeout = Keyword.get(config, :timeout_ms) || @default_timeout_ms
    req_options = Keyword.get(config, :req_options, [])

    body = Map.put(payload, "model", model)

    request_opts =
      [
        url: base_url <> "/v1/messages",
        method: :post,
        json: body,
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", @anthropic_version}
        ],
        receive_timeout: timeout,
        retry: false
      ] ++ req_options

    try do
      case Req.request(request_opts) do
        {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
          parse_body(resp_body)

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          Logger.warning("Anthropic API returned HTTP #{status}: #{inspect(resp_body)}")
          {:error, {:http_status, status}}

        {:error, reason} ->
          Logger.warning("Anthropic API request failed: #{inspect(reason)}")
          {:error, {:transport, reason}}
      end
    rescue
      exception ->
        Logger.warning("Anthropic API request raised: #{inspect(exception)}")
        {:error, {:exception, exception}}
    end
  end

  defp parse_body(body) when is_map(body), do: {:ok, body}
  defp parse_body(_), do: {:error, :malformed_response}

  defp config do
    Application.get_env(:agenticrealms, __MODULE__, [])
  end
end
