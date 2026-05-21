defmodule AgenticRealms.World.Examine.Match do
  @moduledoc """
  Successful examine resolution. `target_kind` discriminates the two
  payload shapes:

    * `:object` — `name` is the object's stored name (`world_objects.name`
      preserved casing); `long_description` is `world_objects.long_description`
      verbatim.
    * `:player` — `name` is the matched player's display username
      (`account_players.username` preserved casing); `long_description` is
      `nil` — the player render branch hard-codes the placeholder body.

  See `specs/006-examine-objects/data-model.md` §1.
  """

  @enforce_keys [:target_kind, :name]
  defstruct [:target_kind, :name, :long_description]

  @type t :: %__MODULE__{
          target_kind: :object | :player,
          name: String.t(),
          long_description: String.t() | nil
        }
end
