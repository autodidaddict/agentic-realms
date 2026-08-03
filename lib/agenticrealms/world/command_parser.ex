defmodule AgenticRealms.World.CommandParser do
  @moduledoc """
  Parse the player's raw text input into a structured command sentinel.

  Pure function: no DB, no aggregates, no dispatch. Owns FR-006 (movement
  aliases), FR-014 (inventory aliases), FR-017 (case/whitespace tolerance),
  FR-018 (unknown commands), and FR-019 (empty input) from feature 003 plus
  the four communication verbs from feature 004 (say, emote, tell, whisper).

  Case-handling contract:

    * **Verbs** are matched case-insensitively (against a downcased copy of the
      first word).
    * **Existing 003 verb payloads** (take/drop target names) are returned
      lowercased — downstream lookups (`Queries.resolve_object_in_room/2`)
      depend on this.
    * **Communication-verb payloads** (`<text>` for say/emote/tell/whisper,
      `<recipient>` for tell/whisper) preserve the original casing from the
      input.

  See `specs/003-persisted-world/contracts/parser.md` and
  `specs/004-player-communication/contracts/parser.md`.
  """

  alias AgenticRealms.World.Direction

  @type result ::
          {:empty}
          | {:unknown, String.t()}
          | {:look}
          | {:look, String.t()}
          | {:inventory}
          | {:move, atom()}
          | {:take, String.t()}
          | {:drop, String.t()}
          | {:invalid_take_target}
          | {:invalid_drop_target}
          | {:say, String.t()}
          | {:say_empty}
          | {:emote, String.t()}
          | {:emote_empty}
          | {:tell, String.t(), String.t()}
          | {:tell_no_recipient}
          | {:tell_no_text, String.t()}
          | {:whisper, String.t(), String.t()}
          | {:whisper_no_recipient}
          | {:whisper_no_text, String.t()}
          | {:chat, String.t(), String.t()}
          | {:chat_no_npc}
          | {:chat_no_message, String.t()}

  @take_aliases ~w(take get pick)
  @drop_aliases ~w(drop put)
  @inventory_aliases ~w(inventory inv i)
  @say_aliases ~w(say)
  @emote_aliases ~w(emote me)
  @tell_aliases ~w(tell t)
  @whisper_aliases ~w(whisper)
  @chat_aliases ~w(chat)

  @spec parse(String.t()) :: result()
  def parse(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" ->
        {:empty}

      String.starts_with?(trimmed, "'") ->
        parse_prefix_shortcut(trimmed, "'", &say_sentinel/1)

      String.starts_with?(trimmed, ":") ->
        parse_prefix_shortcut(trimmed, ":", &emote_sentinel/1)

      true ->
        parse_verb(trimmed)
    end
  end

  def parse(_), do: {:unknown, ""}

  defp parse_verb(trimmed) do
    {first_original, rest_original} = split_first_word(trimmed)
    first = String.downcase(first_original)
    rest_lc = String.downcase(rest_original)

    cond do
      first in ["look", "l"] ->
        target = normalize(rest_lc)

        cond do
          target == "" -> {:look}
          target in ["me", "self"] -> {:look, "__self__"}
          true -> {:look, target}
        end

      first in @inventory_aliases ->
        {:inventory}

      first in @take_aliases ->
        if rest_lc == "", do: {:invalid_take_target}, else: {:take, normalize(rest_lc)}

      first in @drop_aliases ->
        if rest_lc == "", do: {:invalid_drop_target}, else: {:drop, normalize(rest_lc)}

      first in @say_aliases ->
        say_sentinel(rest_original)

      first in @emote_aliases ->
        emote_sentinel(rest_original)

      first in @tell_aliases ->
        recipient_text_sentinel(rest_original, :tell)

      first in @whisper_aliases ->
        recipient_text_sentinel(rest_original, :whisper)

      first in @chat_aliases ->
        chat_sentinel(rest_original)

      true ->
        case Direction.parse(String.downcase(trimmed)) do
          {:ok, dir} -> {:move, dir}
          :error -> {:unknown, trimmed}
        end
    end
  end

  defp say_sentinel(text) do
    case String.trim(text) do
      "" -> {:say_empty}
      t -> {:say, t}
    end
  end

  defp emote_sentinel(text) do
    case String.trim(text) do
      "" -> {:emote_empty}
      t -> {:emote, t}
    end
  end

  defp recipient_text_sentinel(rest, kind) do
    case String.split(rest, ~r/\s+/, parts: 2) do
      [""] ->
        no_recipient(kind)

      [recipient] ->
        no_text(kind, recipient)

      [recipient, text] ->
        case String.trim(text) do
          "" -> no_text(kind, recipient)
          t -> {kind, recipient, t}
        end
    end
  end

  defp no_recipient(:tell), do: {:tell_no_recipient}
  defp no_recipient(:whisper), do: {:whisper_no_recipient}
  defp no_text(:tell, recipient), do: {:tell_no_text, recipient}
  defp no_text(:whisper, recipient), do: {:whisper_no_text, recipient}

  defp chat_sentinel(rest) do
    case String.split(rest, ~r/\s+/, parts: 2) do
      [""] ->
        {:chat_no_npc}

      [npc_token] ->
        {:chat_no_message, npc_token}

      [npc_token, message] ->
        case String.trim(message) do
          "" -> {:chat_no_message, npc_token}
          m -> {:chat, npc_token, m}
        end
    end
  end

  defp parse_prefix_shortcut(trimmed, prefix, sentinel_fn) do
    rest =
      trimmed
      |> String.replace_prefix(prefix, "")
      |> String.replace_prefix(" ", "")

    sentinel_fn.(rest)
  end

  defp split_first_word(s) do
    case String.split(s, ~r/\s+/, parts: 2) do
      [first] -> {first, ""}
      [first, rest] -> {first, String.trim_leading(rest)}
    end
  end

  defp normalize(s) do
    s
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join(" ")
  end
end
