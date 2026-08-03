defmodule AgenticRealms.World.Blueprint.Slug do
  @moduledoc """
  Blueprint slug helpers. One namespace across both kinds.

  - `derive/1` produces the candidate slug a wizard sees pre-populated in
    the form when authoring a new blueprint: lowercase, non-alphanumeric
    runs collapsed to `_`, leading/trailing `_` trimmed.
  - `valid?/1` enforces the regex `^[a-z][a-z0-9_]*$` and length 1–64.

  UUID-shaped strings are explicitly rejected by `valid?/1` — they fail the
  leading-letter rule and the `-` character.
  """

  @max_length 64
  @valid_regex ~r/\A[a-z][a-z0-9_]*\z/

  @spec derive(String.t()) :: String.t()
  def derive(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> ensure_leading_letter()
    |> String.slice(0, @max_length)
  end

  @spec valid?(term()) :: boolean()
  def valid?(slug) when is_binary(slug) do
    String.length(slug) in 1..@max_length and Regex.match?(@valid_regex, slug)
  end

  def valid?(_), do: false

  defp ensure_leading_letter(""), do: ""

  defp ensure_leading_letter(<<first, _::binary>> = candidate)
       when first in ?a..?z,
       do: candidate

  defp ensure_leading_letter(candidate), do: "b_" <> candidate
end
