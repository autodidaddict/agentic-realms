defmodule AgenticRealms.World.Commands.EditObject do
  @moduledoc """
  Feature 014 US5 — edit a world Object in place. No revision counter
  (Objects don't have one in milestone 1); last-write-wins is acceptable
  for the rare co-edit case. Routed to the Room aggregate that currently
  contains the object.

  `fields_changed` is a sparse diff of `:name` / `:short_description` /
  `:long_description` / `:fixed`.

  See `specs/014-item-blueprints/contracts/commands.md`.
  """

  @enforce_keys [:room_id, :object_id, :wizard_id, :fields_changed]
  defstruct [:room_id, :object_id, :wizard_id, :fields_changed]
end
