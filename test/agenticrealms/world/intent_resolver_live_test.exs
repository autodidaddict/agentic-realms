defmodule AgenticRealms.World.IntentResolverLiveTest do
  @moduledoc """
  Live smoke test for the intent resolver — issues a curated set of
  natural-language inputs against the REAL Anthropic Messages API and asserts
  the model selected the right tool.

  Tagged `:live_llm` and excluded from the default `mix test` run: it costs
  real API tokens and needs network access. Run on demand with:

      ANTHROPIC_API_KEY=sk-ant-... mix test --include live_llm \\
        test/agenticrealms/world/intent_resolver_live_test.exs

  If `ANTHROPIC_API_KEY` is unset the test self-skips so an explicit
  `--include live_llm` on a machine without a key doesn't hard-fail.

  This exercises the real system prompt, the real tool definitions, the real
  model, and the real `parse_response/1` mapping. It builds the request
  directly (system + tools + a synthetic context message) so it does not need
  a seeded database — the DB-backed context build is just string formatting
  and is covered by `ContextSnapshotTest`.
  """
  use ExUnit.Case, async: false

  @moduletag :live_llm
  # Real API round-trips are slow; give the whole case generous headroom.
  @moduletag timeout: 120_000

  alias AgenticRealms.World.IntentResolver
  alias AgenticRealms.World.IntentResolver.{SystemPrompt, Tools}

  # {player input, expected outcome}.  :refuse means the `refuse` tool;
  # everything else is the expected action-tuple verb (first element).
  @cases [
    {"grab the brass lantern off the floor", :take},
    {"put down the journal", :drop},
    {"head north", :move},
    {"let me see the room", :look},
    {"what am I carrying right now", :inventory},
    {"say hello to everyone here", :say},
    {"wave cheerfully at the fire", :emote},
    {"tell alice I will be right back", :tell},
    {"lean in and quietly tell bob to watch out", :whisper},
    {"examine the brass lantern very closely", :refuse},
    {"take the lantern and then head north", :refuse},
    {"what time is it in the real world", :refuse}
  ]

  setup_all do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" ->
        original = Application.get_env(:agenticrealms, AgenticRealms.Anthropic)

        # Point at the real API: real key, drop the Req.Test plug.
        Application.put_env(
          :agenticrealms,
          AgenticRealms.Anthropic,
          original
          |> Keyword.put(:api_key, key)
          |> Keyword.put(:base_url, "https://api.anthropic.com")
          |> Keyword.delete(:req_options)
        )

        on_exit(fn ->
          Application.put_env(:agenticrealms, AgenticRealms.Anthropic, original)
        end)

        :ok

      _ ->
        # No key — skip the whole case.
        {:ok, skip: true}
    end
  end

  test "the model selects the correct tool for a curated input set", context do
    if context[:skip] do
      IO.puts("\n[live_llm] ANTHROPIC_API_KEY not set — skipping live smoke test.")
    else
      results =
        for {input, expected} <- @cases do
          {input, expected, classify(input)}
        end

      failures =
        Enum.reject(results, fn {_input, expected, actual} -> actual == expected end)

      for {input, expected, actual} <- results do
        IO.puts("[live_llm] #{inspect(input)} → expected #{expected}, got #{actual}")
      end

      assert failures == [],
             "live tool-selection mismatches: " <>
               Enum.map_join(failures, "; ", fn {input, exp, act} ->
                 "#{inspect(input)} expected #{exp} got #{act}"
               end)
    end
  end

  # Build a real Anthropic request for `input`, call the API, and reduce the
  # response to the chosen verb atom (`:refuse` for the refuse tool).
  defp classify(input) do
    request = %{
      "max_tokens" => 256,
      "system" => [%{"type" => "text", "text" => SystemPrompt.text()}],
      "tools" => Tools.list(),
      "tool_choice" => %{"type" => "any"},
      "messages" => [
        %{
          "role" => "user",
          "content" => """
          Current room: Stone Atrium
          Exits: north (Forest Path), east (Corridor)
          Objects here: brass lantern, leather-bound journal
          Other players present: alice, bob
          Your inventory: leather-bound journal

          Player typed: #{input}
          """
        }
      ]
    }

    case AgenticRealms.Anthropic.create_message(request) do
      {:ok, response} ->
        case IntentResolver.parse_response(response) do
          {:ok, action} -> elem(action, 0)
          {:error, _message} -> :refuse
        end

      {:error, reason} ->
        flunk("live Anthropic call failed: #{inspect(reason)}")
    end
  end
end
