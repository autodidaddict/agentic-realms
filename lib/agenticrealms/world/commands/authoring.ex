defmodule AgenticRealms.World.Commands.Authoring do
  @moduledoc """
  Write-side facade for what a wizard authors and spawns: Blueprints of either
  kind (features 008, 014, 015), spawning from one or freeform, extracting a
  blueprint from something already in the world, and editing an in-world object
  or NPC in place.

  These arrived as three features and share one set of helpers — wizard
  authorization, slug validation, behavior and behavior-group validation, and
  the co-location checks that keep a wizard from editing across the map. They
  are one concern in practice, so they live in one module.

  Split out of `AgenticRealms.World.Commands`, which had grown to cover every
  bounded concern in the world behind one module. `Commands` still delegates
  here, so callers are unchanged.
  """

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.BehaviorGroups
  alias AgenticRealms.World.Blueprint.Slug
  alias AgenticRealms.World.Commands.{CreateBlueprint, EditBlueprint, EditEntity}
  alias AgenticRealms.World.Commands.Entities
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Blueprint, NPCClone, Room}

  @doc """
  Spawn a clone of `blueprint_id` into `room_id` with the given `clone_id`.

  Pre-dispatch validation:
    * blueprint exists (`:blueprint_not_found`)
    * room exists (`:room_not_found`)
    * no other clone in this room shares the blueprint's display name
      (`:clone_name_taken_in_room` — preserves feature 007 FR-001a)

  On success, clones the NPC into existence and moves it into the room via
  the entity lifecycle (`Entities.clone_into(:npc, …)`), with the blueprint's current
  data (incl. its `blueprint_id` reference, behaviors and lore) copied into
  the `EntityCloned` payload (full-copy at dispatch time). Returns
  `{:ok, %{clone_id: clone_id}}`.

  See `specs/008-npc-blueprints/contracts/commands.md`.
  """
  @spec spawn_npc_clone(String.t(), String.t(), String.t()) ::
          {:ok, %{clone_id: String.t()}}
          | {:error,
             :blueprint_not_found
             | :room_not_found
             | :clone_name_taken_in_room
             | :clone_id_already_used
             | term()}
  def spawn_npc_clone(blueprint_id, room_id, clone_id)
      when is_binary(blueprint_id) and is_binary(room_id) and is_binary(clone_id) do
    with {:ok, blueprint} <- fetch_npc_blueprint(blueprint_id) do
      spawn_npc_clone_row(blueprint, room_id, clone_id)
    end
  end

  defp spawn_npc_clone_row(%Blueprint{} = bp, room_id, clone_id) do
    with :ok <- check_room_exists(room_id),
         :ok <- check_no_clone_name_collision(room_id, bp.name),
         {:ok, effective} <- BehaviorGroups.compose(bp.behavior_groups || [], bp.behaviors || []) do
      fields =
        %{
          blueprint_id: bp.id,
          name: bp.name,
          short_description: bp.short_description,
          long_description: bp.long_description,
          behaviors: effective,
          direct_behaviors: bp.behaviors || [],
          behavior_groups: bp.behavior_groups || [],
          lore: bp.lore || "",
          fixed: bp.fixed
        }
        |> Map.merge(npc_stat_fields(bp))

      case Entities.clone_into(:npc, clone_id, fields, ContainerRef.room(room_id), :spawned) do
        {:ok, _} -> {:ok, %{clone_id: clone_id}}
        {:error, _} = err -> err
      end
    end
  end

  defp npc_stat_fields(%Blueprint{} = bp) do
    %{
      str: bp.str,
      dex: bp.dex,
      con: bp.con,
      int: bp.int,
      wis: bp.wis,
      cha: bp.cha,
      level: bp.level,
      hp: bp.max_hp,
      max_hp: bp.max_hp,
      mana: bp.max_mana,
      max_mana: bp.max_mana
    }
  end

  defp default_npc_stat_fields do
    %{
      str: 12,
      dex: 12,
      con: 12,
      int: 12,
      wis: 12,
      cha: 12,
      level: 1,
      hp: 10,
      max_hp: 10,
      mana: 10,
      max_mana: 10
    }
  end

  defp fetch_npc_blueprint(blueprint_id) do
    case Repo.get(Blueprint, blueprint_id) do
      nil -> {:error, :blueprint_not_found}
      %Blueprint{kind: "npc"} = bp -> {:ok, bp}
      %Blueprint{} -> {:error, :blueprint_not_found}
    end
  end

  defp check_room_exists(room_id) do
    case Repo.get(Room, room_id) do
      %Room{} -> :ok
      nil -> {:error, :room_not_found}
    end
  end

  defp check_no_clone_name_collision(room_id, name) do
    case Queries.find_clone_in_room_by_name(room_id, name) do
      {:ok, _clone} -> {:error, :clone_name_taken_in_room}
      {:error, :no_such_clone} -> :ok
    end
  end

  @doc """
  Author a new Blueprint of either kind (`"object"` | `"npc"`).

  FR-WIZ-5 authorization, FR-004 slug-shape + one-namespace uniqueness, and —
  for `kind: "npc"` — validates the direct `behaviors` against the feature-009
  vocabulary (FR-014) and every referenced `behavior_group` against the registry
  (FR-018). `behaviors` are the DIRECT behaviors; the effective set is composed
  (union with behavior_groups) at spawn time.

  Returns `{:ok, blueprint_id}`. Refusals: `:not_a_wizard` / `:unknown_player`,
  `:invalid_slug` / `:slug_already_exists`, the `*_required` content errors,
  `{:unknown_behavior_group, name}`, or a feature-009 behavior-validation error.

  `create_object_blueprint/2` and `create_npc_blueprint/2` are thin wrappers
  that fix `kind`.
  """
  @spec create_blueprint(map(), keyword()) ::
          {:ok, String.t()} | {:error, atom()} | {:error, {:unknown_behavior_group, String.t()}}
  def create_blueprint(attrs, _opts \\ []) when is_map(attrs) do
    kind = Map.get(attrs, :kind, "npc")
    behaviors = Map.get(attrs, :behaviors, []) || []
    behavior_groups = Map.get(attrs, :behavior_groups, []) || []

    with :ok <- ensure_wizard(attrs[:wizard_id]),
         :ok <- validate_slug(attrs[:blueprint_id]),
         :ok <- ensure_slug_unused(attrs[:blueprint_id]),
         :ok <- validate_kind_payload(kind, behaviors, behavior_groups) do
      cmd = %CreateBlueprint{
        blueprint_id: attrs[:blueprint_id],
        wizard_id: attrs[:wizard_id],
        kind: kind,
        name: attrs[:name],
        short_description: attrs[:short_description],
        long_description: attrs[:long_description],
        lore: Map.get(attrs, :lore, "") || "",
        behaviors: behaviors,
        fixed: Map.get(attrs, :fixed, false),
        behavior_groups: behavior_groups
      }

      case WorldApp.dispatch(cmd, consistency: :strong) do
        :ok -> {:ok, attrs[:blueprint_id]}
        {:error, _} = err -> err
      end
    end
  end

  defp validate_kind_payload("npc", behaviors, behavior_groups) do
    with :ok <- BehaviorGroups.validate_behaviors(behaviors) do
      BehaviorGroups.all_exist?(behavior_groups)
    end
  end

  defp validate_kind_payload(_kind, _behaviors, _behavior_groups), do: :ok

  @doc "Author an object blueprint (thin wrapper over `create_blueprint/2`)."
  @spec create_object_blueprint(map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def create_object_blueprint(attrs, opts \\ []) when is_map(attrs),
    do: create_blueprint(Map.put(attrs, :kind, "object"), opts)

  @doc "Author an npc blueprint (thin wrapper over `create_blueprint/2`)."
  @spec create_npc_blueprint(map(), keyword()) ::
          {:ok, String.t()} | {:error, atom()} | {:error, {:unknown_behavior_group, String.t()}}
  def create_npc_blueprint(attrs, opts \\ []) when is_map(attrs),
    do: create_blueprint(Map.put(attrs, :kind, "npc"), opts)

  @doc """
  Spawn a clone of a Blueprint (either kind) into a room — the unified UI
  spawn path. FR-WIZ-5 authorization; resolves the blueprint from the read
  model and stamps the denormalized fields into the clone (full-copy, FR-013):

    * object → `Entities.clone_into(:object, …)`.
    * npc → `BehaviorGroups.compose(behavior_groups, behaviors)` → effective behaviors,
      then `Entities.clone_into(:npc, …)` carrying the behavior_group/direct-behavior
      provenance; with the per-room name-collision pre-check (FR-013).

  Returns `{:ok, entity_id}`. Refusals: `:not_a_wizard` / `:unknown_player`,
  `:unknown_blueprint`, `:room_not_found`, `:clone_name_taken_in_room`,
  `{:unknown_behavior_group, name}`.
  """
  @spec spawn_from_blueprint(integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def spawn_from_blueprint(wizard_id, blueprint_id, room_id)
      when is_integer(wizard_id) and is_binary(blueprint_id) and is_binary(room_id) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, bp} <- fetch_any_blueprint(blueprint_id) do
      case bp.kind do
        "object" ->
          Entities.clone_into(
            :object,
            %{
              name: bp.name,
              short_description: bp.short_description,
              long_description: bp.long_description,
              fixed: bp.fixed,
              behaviors: [],
              quest_player_id: nil,
              quest_instance_id: nil
            },
            ContainerRef.room(room_id),
            :spawned
          )

        "npc" ->
          case spawn_npc_clone_row(bp, room_id, Ecto.UUID.generate()) do
            {:ok, %{clone_id: id}} -> {:ok, id}
            {:error, _} = err -> err
          end
      end
    end
  end

  @doc "Object-only spawn (thin wrapper over `spawn_from_blueprint/3`)."
  @spec spawn_object_from_blueprint(integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def spawn_object_from_blueprint(wizard_id, blueprint_id, room_id),
    do: spawn_from_blueprint(wizard_id, blueprint_id, room_id)

  defp fetch_any_blueprint(blueprint_id) do
    case Repo.get(Blueprint, blueprint_id) do
      nil -> {:error, :unknown_blueprint}
      bp -> {:ok, bp}
    end
  end

  @doc """
  Spawn a freeform Object into a room — no Object Blueprint involvement,
  no registry change. The wizard's authored payload is cloned into the
  room via the entity lifecycle (`Entities.clone_into(:object, …)`, feature 016).

  Returns `{:ok, object_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` — caller's `is_wizard` is false.
    * `{:error, :unknown_player}` — caller's player_id is unknown.
    * `{:error, :name_required}` / `:short_description_required` /
      `:long_description_required` — required content field missing.
  """
  @spec spawn_object_freeform(
          wizard_id :: integer(),
          room_id :: String.t(),
          attrs :: %{
            required(:name) => String.t(),
            required(:short_description) => String.t(),
            required(:long_description) => String.t(),
            optional(:fixed) => boolean()
          }
        ) :: {:ok, String.t()} | {:error, atom()}
  def spawn_object_freeform(wizard_id, room_id, attrs)
      when is_integer(wizard_id) and is_binary(room_id) and is_map(attrs) do
    with :ok <- ensure_wizard(wizard_id),
         :ok <- validate_object_attrs(attrs) do
      Entities.clone_into(
        :object,
        %{
          name: attrs[:name],
          short_description: attrs[:short_description],
          long_description: attrs[:long_description],
          fixed: Map.get(attrs, :fixed, false),
          behaviors: [],
          quest_player_id: nil,
          quest_instance_id: nil
        },
        ContainerRef.room(room_id),
        :spawned
      )
    end
  end

  @doc """
  Spawn a freeform one-off NPC into a room — no Blueprint, no registry change
  (feature 015 US5). The wizard's authored payload (incl. `lore`) is cloned
  into the room via `Entities.clone_into(:npc, …)` with a null `blueprint_id`/`serial`,
  so the clone is observationally identical to a blueprint-spawned NPC but has
  no template behind it.

  Refusals: `:not_a_wizard` / `:unknown_player`, the `*_required` content
  errors, `:room_not_found`, `:clone_name_taken_in_room`.
  """
  @spec spawn_npc_freeform(
          wizard_id :: integer(),
          room_id :: String.t(),
          attrs :: %{
            required(:name) => String.t(),
            required(:short_description) => String.t(),
            required(:long_description) => String.t(),
            optional(:lore) => String.t(),
            optional(:fixed) => boolean(),
            optional(:behaviors) => [map()]
          }
        ) :: {:ok, String.t()} | {:error, atom()}
  def spawn_npc_freeform(wizard_id, room_id, attrs)
      when is_integer(wizard_id) and is_binary(room_id) and is_map(attrs) do
    behaviors = Map.get(attrs, :behaviors, []) || []

    with :ok <- ensure_wizard(wizard_id),
         :ok <- validate_object_attrs(attrs),
         :ok <- BehaviorGroups.validate_behaviors(behaviors),
         :ok <- check_room_exists(room_id),
         :ok <- check_no_clone_name_collision(room_id, attrs[:name]) do
      fields =
        %{
          blueprint_id: nil,
          name: attrs[:name],
          short_description: attrs[:short_description],
          long_description: attrs[:long_description],
          behaviors: behaviors,
          direct_behaviors: behaviors,
          behavior_groups: [],
          lore: Map.get(attrs, :lore, "") || "",
          fixed: Map.get(attrs, :fixed, false)
        }
        |> Map.merge(default_npc_stat_fields())

      case Entities.clone_into(
             :npc,
             Ecto.UUID.generate(),
             fields,
             ContainerRef.room(room_id),
             :spawned
           ) do
        {:ok, entity_id} -> {:ok, entity_id}
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  One-shot extract-essence — read an in-world entity's denormalized fields and
  persist a new Blueprint at `revision: 1` (FR-012 / FR-016 / FR-018). The
  source entity is NOT modified. The entity kind is detected from its id: a
  world Object yields an object blueprint; an NPC clone yields an npc blueprint
  (copying its lore + DIRECT behaviors + behavior_group names, so the new blueprint
  recomposes the same effective set — not the frozen union).

  Returns `{:ok, blueprint_id}`. Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_entity}` — `entity_id` is not an extractable object or
      NPC clone (incl. a quest-scoped object, which wizards do not extract).
    * `{:error, :invalid_slug}` / `{:error, :slug_already_exists}`.
    * (npc) `{:error, {:unknown_behavior_group, name}}` / a feature-009 behavior error.

  Intended for `iex` / test setup; the LiveView paths (`extract_essence` /
  `extract_npc_essence` events) instead pre-populate the trance card and let the
  wizard refine the draft before the normal `commit_blueprint_draft` flow.
  """
  @spec extract_essence(integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def extract_essence(wizard_id, entity_id, proposed_slug)
      when is_integer(wizard_id) and is_binary(entity_id) and is_binary(proposed_slug) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, source} <- fetch_extractable_entity(entity_id) do
      case source do
        {:object, object} ->
          create_object_blueprint(%{
            wizard_id: wizard_id,
            blueprint_id: proposed_slug,
            name: object.name,
            short_description: object.short_description,
            long_description: object.long_description,
            fixed: object.fixed
          })

        {:npc, clone} ->
          create_npc_blueprint(%{
            wizard_id: wizard_id,
            blueprint_id: proposed_slug,
            name: clone.name,
            short_description: clone.short_description,
            long_description: clone.long_description,
            lore: clone.lore || "",
            fixed: clone.fixed,
            behaviors: clone.direct_behaviors || [],
            behavior_groups: clone.behavior_groups || []
          })
      end
    end
  end

  defp fetch_extractable_entity(entity_id) do
    case fetch_object(entity_id) do
      {:ok, object} ->
        {:ok, {:object, object}}

      {:error, _} ->
        case fetch_npc_clone_row(entity_id) do
          {:ok, clone} -> {:ok, {:npc, clone}}
          {:error, _} -> {:error, :unknown_entity}
        end
    end
  end

  defp fetch_npc_clone_row(clone_id) do
    case Repo.get(NPCClone, clone_id) do
      nil -> {:error, :unknown_npc}
      clone -> {:ok, clone}
    end
  end

  defp fetch_object(object_id) do
    case Repo.get(AgenticRealms.World.Schemas.Object, object_id) do
      nil ->
        {:error, :unknown_object}

      %{quest_player_id: pid} when not is_nil(pid) ->
        {:error, :unknown_object}

      o ->
        {:ok, o}
    end
  end

  @object_only_edit_fields ~w(name short_description long_description fixed)a
  @edit_blueprint_fields ~w(name short_description long_description fixed lore behavior_groups behaviors)a

  @doc """
  Edit an existing Object Blueprint. `expected_revision` MUST equal the
  blueprint's current revision (FR-020a). On stale revision the wrapper
  returns `{:error, :stale_revision, current_revision: N}` so the
  LiveView can reload the form with the latest values.

  Returns `{:ok, new_revision}` on a field-changing commit. Returns
  `{:ok, :no_change}` when every field in `fields_changed` already
  equals the current state (FR-008 — no revision bump for no-op).

  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_blueprint}`.
    * `{:error, :invalid_field}` — `fields_changed` contains an
      unrecognized key.
    * `{:error, :stale_revision, current_revision: N}` — optimistic
      lock fired.
  """
  @spec edit_object_blueprint(
          wizard_id :: integer(),
          blueprint_id :: String.t(),
          %{
            required(:expected_revision) => integer(),
            required(:fields_changed) => map()
          }
        ) ::
          {:ok, new_revision :: integer()}
          | {:ok, :no_change}
          | {:error, atom()}
          | {:error, :stale_revision, [current_revision: integer()]}
  def edit_object_blueprint(wizard_id, blueprint_id, params)
      when is_integer(wizard_id) and is_binary(blueprint_id) and is_map(params) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, blueprint} <- fetch_any_blueprint(blueprint_id),
         :ok <- validate_edit_fields(params[:fields_changed], @edit_blueprint_fields),
         :ok <- validate_edit_payload(params[:fields_changed]) do
      cmd = %EditBlueprint{
        blueprint_id: blueprint_id,
        wizard_id: wizard_id,
        expected_revision: params[:expected_revision],
        fields_changed: params[:fields_changed]
      }

      case WorldApp.dispatch(cmd, consistency: :strong) do
        :ok ->
          updated = Repo.get(Blueprint, blueprint_id)

          cond do
            updated.revision == blueprint.revision -> {:ok, :no_change}
            true -> {:ok, updated.revision}
          end

        {:error, :stale_revision} ->
          current = Repo.get(Blueprint, blueprint_id)
          {:error, :stale_revision, current_revision: current.revision}

        {:error, _} = err ->
          err
      end
    end
  end

  defp validate_edit_fields(fields, allowed) when is_map(fields) do
    if Enum.all?(Map.keys(fields), &(&1 in allowed)) do
      :ok
    else
      {:error, :invalid_field}
    end
  end

  defp validate_edit_fields(_, _), do: {:error, :invalid_field}

  defp validate_edit_payload(fields) do
    with :ok <- maybe_validate_behaviors(fields) do
      maybe_validate_behavior_groups(fields)
    end
  end

  defp maybe_validate_behaviors(%{behaviors: behaviors}),
    do: BehaviorGroups.validate_behaviors(behaviors || [])

  defp maybe_validate_behaviors(_), do: :ok

  defp maybe_validate_behavior_groups(%{behavior_groups: behavior_groups}),
    do: BehaviorGroups.all_exist?(behavior_groups || [])

  defp maybe_validate_behavior_groups(_), do: :ok

  @doc """
  Edit a world Object in place. Routes through the Room aggregate that
  currently contains the object; the wrapper looks up the object's
  current `room_id` from the read model so callers don't need to know.

  Returns `{:ok, :updated}` on a field-changing commit, `{:ok, :no_change}`
  on a no-op diff.

  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_object}` — object_id not in `world_objects`, OR
      object is quest-scoped (wizards do not edit per-player quest items
      in milestone 1).
    * `{:error, :object_not_editable_here}` — object is not currently
      in a room (e.g., carried by a player) OR it is in a different
      room than the wizard's current room. Per `contracts/commands.md`,
      both halves of this clause are part of the contract; the
      same-room enforcement here is the security boundary that the
      LiveView's focus-time pattern match (the UX gate) sits in front
      of.
    * `{:error, :invalid_field}`.
  """
  @spec edit_object(
          wizard_id :: integer(),
          object_id :: String.t(),
          fields_changed :: map()
        ) :: {:ok, :updated | :no_change} | {:error, atom()}
  def edit_object(wizard_id, object_id, fields_changed)
      when is_integer(wizard_id) and is_binary(object_id) and is_map(fields_changed) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, object} <- fetch_object(object_id),
         :ok <- validate_edit_fields(fields_changed, @object_only_edit_fields),
         {:ok, room_id} <- ensure_in_room(object),
         :ok <- ensure_wizard_co_located(wizard_id, room_id) do
      diff = only_actual_diff(object, fields_changed)

      cond do
        map_size(diff) == 0 ->
          {:ok, :no_change}

        true ->
          _ = room_id

          case WorldApp.dispatch(
                 %EditEntity{entity_id: object_id, fields_changed: diff},
                 consistency: :strong
               ) do
            :ok -> {:ok, :updated}
            {:error, _} = err -> err
          end
      end
    end
  end

  @doc """
  Feature 015 US7 — edit an in-world NPC clone in place. Co-located security
  boundary: the clone must be in the wizard's current room. The clone is
  freestanding, so the edit applies only to it (no propagation to the
  blueprint or sibling clones).

  Returns `{:ok, :updated | :no_change}`. Refusals: `:not_a_wizard` /
  `:unknown_player`, `:unknown_npc`, `:invalid_field`, a behavior/behavior_group
  validation error, or `:object_not_editable_here` (clone not co-located).
  """
  @spec edit_npc(integer(), String.t(), map()) :: {:ok, :updated | :no_change} | {:error, term()}
  def edit_npc(wizard_id, clone_id, fields_changed)
      when is_integer(wizard_id) and is_binary(clone_id) and is_map(fields_changed) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, clone} <- fetch_npc_clone_row(clone_id),
         :ok <- validate_edit_fields(fields_changed, @edit_blueprint_fields),
         :ok <- validate_edit_payload(fields_changed),
         :ok <- ensure_npc_co_located(wizard_id, clone.room_id) do
      diff = only_actual_diff(clone, fields_changed)

      if map_size(diff) == 0 do
        {:ok, :no_change}
      else
        case WorldApp.dispatch(
               %EditEntity{entity_id: clone_id, fields_changed: diff},
               consistency: :strong
             ) do
          :ok -> {:ok, :updated}
          {:error, _} = err -> err
        end
      end
    end
  end

  defp ensure_npc_co_located(wizard_id, room_id) when is_binary(room_id) do
    ensure_wizard_co_located(wizard_id, room_id)
  end

  defp ensure_npc_co_located(_wizard_id, _room_id), do: {:error, :object_not_editable_here}

  defp ensure_in_room(%{container_type: "room", container_id: rid}) when is_binary(rid),
    do: {:ok, rid}

  defp ensure_in_room(_), do: {:error, :object_not_editable_here}

  defp ensure_wizard_co_located(wizard_id, object_room_id) do
    case AgenticRealms.World.Queries.current_room_of(wizard_id) do
      {:ok, ^object_room_id} -> :ok
      _ -> {:error, :object_not_editable_here}
    end
  end

  defp only_actual_diff(object, fields_changed) do
    fields_changed
    |> Enum.reject(fn {k, v} -> Map.get(object, k) == v end)
    |> Map.new()
  end

  defp validate_object_attrs(attrs) do
    cond do
      blank?(attrs[:name]) -> {:error, :name_required}
      blank?(attrs[:short_description]) -> {:error, :short_description_required}
      blank?(attrs[:long_description]) -> {:error, :long_description_required}
      true -> :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: true

  defp validate_slug(slug) do
    if Slug.valid?(slug), do: :ok, else: {:error, :invalid_slug}
  end

  defp ensure_slug_unused(slug) do
    case Repo.get(Blueprint, slug) do
      nil -> :ok
      _ -> {:error, :slug_already_exists}
    end
  end

  defp ensure_wizard(player_id) when is_integer(player_id) do
    case Accounts.get_player(player_id) do
      %Accounts.Player{is_wizard: true} -> :ok
      %Accounts.Player{is_wizard: false} -> {:error, :not_a_wizard}
      nil -> {:error, :unknown_player}
    end
  end

  defp ensure_wizard(_), do: {:error, :unknown_player}
end
