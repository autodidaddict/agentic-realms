defmodule AgenticRealms.EventStore.Serializer do
  @moduledoc """
  Event store serializer used by `AgenticRealms.EventStore` (the Commanded
  EventStore adapter) in dev and prod.

  `Jason.encode!/1` on serialize. On deserialize, JSON decodes to string keys,
  the **struct's own field names** are matched against them, and the result is
  piped through `Commanded.Serialization.JsonDecoder.decode/1` so aggregate
  snapshots can rehydrate non-JSON-native fields (e.g. `MapSet`) via
  per-aggregate impls.

  Event types that don't implement `JsonDecoder` fall through the default `Any`
  impl unchanged.

  ## Why not `keys: :atoms!`

  It used to be `Jason.decode!(binary, keys: :atoms!)`, which is the obvious
  thing and is wrong in a way that hides for a long time. That option atomizes
  keys at **every** nesting level, not just the struct's fields — so a `Room`
  snapshot whose `exits` are `%{"north" => id}` had its *data* keys converted
  too, and `binary_to_existing_atom("north")` only succeeds if something has
  already loaded `World.Direction`.

  Whether it had was a function of module load order. In tests that meant the
  seed; on a cold node it meant whether anything had touched directions before
  the first snapshot was read. It surfaced as a genuinely seed-dependent CI
  failure, and it was a class of bug rather than one instance: any data-keyed
  map in any persisted payload was exposed.

  Matching the struct's declared fields avoids it entirely. Those atoms exist by
  definition — the struct names them — and nothing below the top level is
  touched, so data keys stay the strings they were serialized as. Consumers that
  read nested payloads already handle either form through
  `AgenticRealms.World.EventData`.
  """

  @behaviour EventStore.Serializer

  alias Commanded.Serialization.JsonDecoder

  @impl true
  def serialize(term), do: Jason.encode!(term)

  @impl true
  def deserialize(binary, config) do
    case Keyword.get(config, :type) do
      nil ->
        Jason.decode!(binary)

      type ->
        module = String.to_existing_atom(type)

        binary
        |> Jason.decode!()
        |> to_struct(module)
        |> JsonDecoder.decode()
    end
  end

  defp to_struct(decoded, module) when is_map(decoded) do
    attrs =
      module.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        case Map.fetch(decoded, Atom.to_string(field)) do
          {:ok, value} -> Map.put(acc, field, value)
          :error -> acc
        end
      end)

    struct(module, attrs)
  end
end
