defmodule AgenticRealms.EventStore.Serializer do
  @moduledoc """
  Event store serializer used by `AgenticRealms.EventStore` (the Commanded
  EventStore adapter) in dev and prod.

  Wire format is identical to `EventStore.JsonSerializer`: `Jason.encode!/1`
  on serialize, `Jason.decode!(... keys: :atoms!)` then `struct(type, data)`
  on deserialize. After struct construction the value is piped through
  `Commanded.Serialization.JsonDecoder.decode/1` so aggregate snapshots can
  rehydrate non-JSON-native fields (e.g. `MapSet`) via per-aggregate impls.

  Event types that don't implement `JsonDecoder` fall through the default
  `Any` impl unchanged, so existing events keep the same behavior they had
  under `EventStore.JsonSerializer`.
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
        type
        |> String.to_existing_atom()
        |> struct(Jason.decode!(binary, keys: :atoms!))
        |> JsonDecoder.decode()
    end
  end
end
