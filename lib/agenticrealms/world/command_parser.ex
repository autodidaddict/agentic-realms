defmodule AgenticRealms.World.CommandParser do
  @moduledoc """
  Parse the player's raw text input into a structured command sentinel.

  Pure function: no DB, no aggregates, no dispatch. Owns FR-006 (movement
  aliases), FR-014 (inventory aliases), FR-017 (case/whitespace tolerance),
  FR-018 (unknown commands), and FR-019 (empty input).

  See `specs/003-persisted-world/contracts/parser.md`.
  """

  alias AgenticRealms.World.Direction

  @type result ::
          {:empty}
          | {:unknown, String.t()}
          | {:look}
          | {:inventory}
          | {:move, atom()}
          | {:take, String.t()}
          | {:drop, String.t()}
          | {:invalid_take_target}
          | {:invalid_drop_target}

  @take_aliases ~w(take get pick)
  @drop_aliases ~w(drop put)
  @inventory_aliases ~w(inventory inv i)

  @spec parse(String.t()) :: result()
  def parse(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    case trimmed do
      "" ->
        {:empty}

      _ ->
        downcased = String.downcase(trimmed)
        {first, rest} = split_first_word(downcased)

        cond do
          first in ["look", "l"] ->
            {:look}

          first in @inventory_aliases ->
            {:inventory}

          first in @take_aliases ->
            if rest == "", do: {:invalid_take_target}, else: {:take, normalize(rest)}

          first in @drop_aliases ->
            if rest == "", do: {:invalid_drop_target}, else: {:drop, normalize(rest)}

          true ->
            case Direction.parse(downcased) do
              {:ok, dir} -> {:move, dir}
              :error -> {:unknown, trimmed}
            end
        end
    end
  end

  def parse(_), do: {:unknown, ""}

  defp split_first_word(s) do
    case String.split(s, ~r/\s+/, parts: 2) do
      [first] -> {first, ""}
      [first, rest] -> {first, String.trim(rest)}
    end
  end

  defp normalize(s) do
    s
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join(" ")
  end
end
