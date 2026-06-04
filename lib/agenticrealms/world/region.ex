defmodule AgenticRealms.World.Region do
  @moduledoc """
  Region aggregate. Owns the named map area to which one or more rooms
  belong. v1 supports creation only — no rename, no delete.

  See `specs/012-maps/data-model.md` §1.1 and
  `specs/012-maps/contracts/region.md`.
  """

  defstruct id: nil, name: nil

  alias AgenticRealms.World.Commands.CreateRegion
  alias AgenticRealms.World.Events.RegionCreated

  # --- CreateRegion -------------------------------------------------------

  @spec execute(%__MODULE__{}, %CreateRegion{}) ::
          %RegionCreated{} | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CreateRegion{region_id: id, name: name}) do
    case validate_name(name) do
      :ok -> %RegionCreated{region_id: id, name: name}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%__MODULE__{}, %CreateRegion{}), do: {:error, :region_already_exists}

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %RegionCreated{}) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %RegionCreated{region_id: id, name: name}) do
    %__MODULE__{state | id: id, name: name}
  end

  # ------------------------------------------------------------------------

  defp validate_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :region_name_blank}
      _ -> :ok
    end
  end

  defp validate_name(_), do: {:error, :region_name_not_a_string}
end
