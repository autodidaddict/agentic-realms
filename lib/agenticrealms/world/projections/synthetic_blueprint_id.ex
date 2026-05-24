defmodule AgenticRealms.World.Projections.SyntheticBlueprintId do
  @moduledoc """
  Deterministic synthetic blueprint id derivation for the legacy event
  replay path (FR-019 / FR-020 / FR-021).

  Same `(name, short_description, long_description)` tuple always produces
  the same id. Different tuples produce different ids. Pure function.

  The id is stored directly in `npc_blueprints.id` (a string column) and
  visually distinguishable from authored slugs by its `synthetic-` prefix.

  See `specs/008-npc-blueprints/contracts/projector.md`.
  """

  @prefix "synthetic-"
  @separator "|"

  @doc """
  Derive a deterministic synthetic blueprint id from an NPC payload.
  """
  @spec derive(String.t(), String.t(), String.t()) :: String.t()
  def derive(name, short, long)
      when is_binary(name) and is_binary(short) and is_binary(long) do
    payload = "#{name}#{@separator}#{short}#{@separator}#{long}"
    digest = :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
    @prefix <> digest
  end
end
