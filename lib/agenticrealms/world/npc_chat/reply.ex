defmodule AgenticRealms.World.NPCChat.Reply do
  @moduledoc """
  Parses an Anthropic Messages API response body into a structured chat
  reply outcome (feature 010). Pure — no I/O.

  Returns `{:speech, text} | {:emote, text} | {:error, :malformed}`.
  Anything that isn't EXACTLY one well-formed `tool_use` block whose
  name is in `Tools.names/0` and whose `input.text` is a non-empty
  trimmed string collapses to `:malformed` (FR-021). Malformed output
  flows through the FR-011 fallback path.

  See `specs/010-npc-conversations/contracts/reply.md`.
  """

  alias AgenticRealms.World.NPCChat.Tools

  @type outcome ::
          {:speech, String.t()}
          | {:emote, String.t()}
          | {:tool_call, %{name: String.t(), input: map()}}
          | {:error, :malformed}

  @spec parse(map() | term()) :: outcome()
  def parse(%{"content" => content}) when is_list(content) do
    tool_uses = Enum.filter(content, &(&1["type"] == "tool_use"))

    case tool_uses do
      [block] -> parse_block(block)
      _ -> {:error, :malformed}
    end
  end

  def parse(_), do: {:error, :malformed}

  defp parse_block(%{"name" => name, "input" => input}) do
    cond do
      not MapSet.member?(Tools.names(), name) ->
        {:error, :malformed}

      name in ["say", "emote"] ->
        parse_text_tool(name, input)

      name == "accept_quest" ->
        parse_quest_tool(name, input, ["slug"])

      name == "check_progress" ->
        parse_quest_tool(name, input, ["quest_id"])

      name == "finalize_quest" ->
        parse_quest_tool(name, input, ["quest_id"])

      true ->
        {:error, :malformed}
    end
  end

  defp parse_block(_), do: {:error, :malformed}

  defp parse_text_tool(name, %{"text" => text}) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:error, :malformed}
      name == "say" -> {:speech, trimmed}
      name == "emote" -> {:emote, trimmed}
    end
  end

  defp parse_text_tool(_, _), do: {:error, :malformed}

  defp parse_quest_tool(name, input, required_keys) when is_map(input) do
    if Enum.all?(required_keys, fn k ->
         is_binary(Map.get(input, k)) and Map.get(input, k) != ""
       end) do
      {:tool_call, %{name: name, input: input}}
    else
      {:error, :malformed}
    end
  end

  defp parse_quest_tool(_, _, _), do: {:error, :malformed}
end
