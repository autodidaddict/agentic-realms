defmodule AgenticRealms.World.ContainerRef do
  @moduledoc """
  A typed reference to the place an entity is contained: the void, a room,
  a player's inventory, or an NPC's inventory. Replaces the ad-hoc
  `room_id`/`player_id` + XOR location model with a single `(type, id)`
  value (feature 016, FR-006/FR-012b).

  The **void** is the null container — `%ContainerRef{type: :void, id: nil}`
  — holding entities that exist but are placed nowhere.

  Serializes to/from a plain map (`%{"type" => ..., "id" => ...}`) for event
  payloads. `from_map/1` is tolerant of struct passthrough and of both
  string- and atom-keyed maps (events come back string-keyed after replay).

  See `specs/016-entity-containment/data-model.md` §1.
  """

  @types ~w(void room player npc)a

  @derive Jason.Encoder
  @enforce_keys [:type]
  defstruct [:type, :id]

  @type t :: %__MODULE__{type: :void | :room | :player | :npc, id: term() | nil}

  @doc "The distinguished null container."
  @spec void() :: t()
  def void, do: %__MODULE__{type: :void, id: nil}

  @spec room(term()) :: t()
  def room(id), do: %__MODULE__{type: :room, id: id}

  @spec player(term()) :: t()
  def player(id), do: %__MODULE__{type: :player, id: id}

  @spec npc(term()) :: t()
  def npc(id), do: %__MODULE__{type: :npc, id: id}

  @doc "The supported container types."
  @spec types() :: [atom()]
  def types, do: @types

  @spec valid_type?(atom()) :: boolean()
  def valid_type?(type), do: type in @types

  @doc """
  Structural validity: the void has a nil id; every other type carries a
  non-nil id.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{type: :void, id: nil}), do: true
  def valid?(%__MODULE__{type: :void}), do: false

  def valid?(%__MODULE__{type: type, id: id}) when type in [:room, :player, :npc],
    do: not is_nil(id)

  def valid?(_), do: false

  @doc "Render to a JSON-friendly map for event payloads."
  @spec to_map(t()) :: %{String.t() => term()}
  def to_map(%__MODULE__{type: type, id: id}), do: %{"type" => Atom.to_string(type), "id" => id}

  @doc """
  Rebuild from whatever form a container arrives in: a `ContainerRef` struct
  (in-process emission), a string-keyed map (after event replay), or an
  atom-keyed map.
  """
  @spec from_map(t() | map()) :: t()
  def from_map(%__MODULE__{} = ref), do: ref

  def from_map(%{"type" => type} = map),
    do: %__MODULE__{type: to_type(type), id: Map.get(map, "id")}

  def from_map(%{type: type} = map),
    do: %__MODULE__{type: to_type(type), id: Map.get(map, :id)}

  @doc "Value equality after normalizing struct/map form."
  @spec equal?(t() | map(), t() | map()) :: boolean()
  def equal?(a, b) do
    na = from_map(a)
    nb = from_map(b)
    na.type == nb.type and na.id == nb.id
  end

  defp to_type(type) when is_atom(type), do: type
  defp to_type(type) when is_binary(type), do: String.to_existing_atom(type)
end
