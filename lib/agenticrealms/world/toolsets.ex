defmodule AgenticRealms.World.Toolsets do
  @moduledoc """
  Feature 015 — the toolset registry + composition.

  A toolset is a named group of feature-009 behaviors, applicable to items,
  NPCs, or rooms (cross-entity), referenced by a blueprint by name. Seed-only
  this milestone (no wizard authoring surface yet), so this is a plain read +
  composition module — no aggregate, no events.

  Composition (`compose/2`) is **additive and lossless** (FR-016): the
  effective behavior list is the concatenation, in attachment order, of each
  referenced toolset's behaviors, followed by the blueprint's direct
  behaviors. Same-trigger behaviors from different sources are all retained
  (feature 009 fires every behavior matching a trigger).
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Behaviors.Validator
  alias AgenticRealms.World.Schemas.Toolset

  @doc "All toolsets, ordered by name (backs the `list_toolsets` LLM tool + picker)."
  @spec list() :: [%Toolset{}]
  def list, do: Repo.all(from(t in Toolset, order_by: t.name))

  @doc "Toolsets applicable to the given entity kind (`:item | :npc | :room`)."
  @spec list_for(:item | :npc | :room) :: [%Toolset{}]
  def list_for(entity) when entity in [:item, :npc, :room] do
    s = Atom.to_string(entity)

    Repo.all(
      from(t in Toolset, where: fragment("? = ANY(?)", ^s, t.applies_to), order_by: t.name)
    )
  end

  @doc """
  Resolve toolset names to their behaviors lists, preserving input order.
  Returns `{:error, {:unknown_toolset, name}}` for the first unknown name
  (FR-018).
  """
  @spec resolve([String.t()]) ::
          {:ok, [[map()]]} | {:error, {:unknown_toolset, String.t()}}
  def resolve(names) when is_list(names) do
    found =
      from(t in Toolset, where: t.name in ^names, select: {t.name, t.behaviors})
      |> Repo.all()
      |> Map.new()

    case Enum.find(names, &(not Map.has_key?(found, &1))) do
      nil -> {:ok, Enum.map(names, &Map.fetch!(found, &1))}
      missing -> {:error, {:unknown_toolset, missing}}
    end
  end

  @doc """
  Compose the effective behavior list = union of the referenced toolsets'
  behaviors (attachment order) ++ the direct behaviors. Additive/lossless.
  """
  @spec compose([String.t()], [map()]) ::
          {:ok, [map()]} | {:error, {:unknown_toolset, String.t()}}
  def compose(toolset_names, direct_behaviors)
      when is_list(toolset_names) and is_list(direct_behaviors) do
    case resolve(toolset_names) do
      {:ok, behavior_lists} -> {:ok, Enum.concat(behavior_lists) ++ direct_behaviors}
      {:error, _} = err -> err
    end
  end

  @doc "Validate behaviors against the feature-009 vocabulary (FR-014). Delegates to `Behaviors.Validator`."
  @spec validate_behaviors([map()]) :: :ok | {:error, term()}
  def validate_behaviors(behaviors), do: Validator.validate(behaviors)

  @doc "Whether every name in `names` exists in the registry."
  @spec all_exist?([String.t()]) :: :ok | {:error, {:unknown_toolset, String.t()}}
  def all_exist?(names) when is_list(names) do
    case resolve(names) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
