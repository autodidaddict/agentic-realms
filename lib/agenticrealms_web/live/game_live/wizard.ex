defmodule AgenticRealmsWeb.GameLive.Wizard do
  @moduledoc """
  Feature 014 — wizard authoring helpers.

  Houses the blueprint and freeform-object commit pipelines, the
  resolver-task outcome dispatcher, the in-flight task canceller, and
  the live blueprint-registry patcher. The matching `handle_event` and
  `handle_info` clauses in `GameLive` delegate straight to these
  functions.
  """

  import Phoenix.Component, only: [assign: 3]

  alias AgenticRealms.World.{Commands, Queries}
  alias AgenticRealms.World.Blueprint.Slug
  alias AgenticRealms.World.Schemas.Blueprint, as: BlueprintRow

  # ────────────────────────────────────────────────────────────
  # Blueprint commit pipeline (US1 / US5)
  # ────────────────────────────────────────────────────────────

  @doc """
  Feature 014 US1 commit-create. Dispatches `create_object_blueprint`,
  refreshes the registry on success, surfaces the error otherwise.
  """
  def commit_blueprint_create(socket, draft) do
    attrs = %{
      wizard_id: socket.assigns.current_player.id,
      blueprint_id: Map.get(draft, :proposed_slug, ""),
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false)
    }

    case Commands.create_object_blueprint(attrs) do
      {:ok, _slug} ->
        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:wizard_prompt, "")
         |> assign(:object_blueprints, Queries.list_object_blueprints())}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  @doc """
  Feature 014 US5 commit-edit. Stale-revision response reloads the
  form with the latest persisted values + surfaces a banner.
  """
  def commit_blueprint_edit(socket, draft, expected_revision) do
    blueprint_id = Map.get(draft, :blueprint_id) || Map.get(draft, :proposed_slug)

    fields_changed = %{
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false)
    }

    case Commands.edit_object_blueprint(
           socket.assigns.current_player.id,
           blueprint_id,
           %{expected_revision: expected_revision, fields_changed: fields_changed}
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:object_blueprints, Queries.list_object_blueprints())}

      {:error, :stale_revision, current_revision: current} ->
        bp = Queries.get_object_blueprint(blueprint_id)

        fresh_draft = %{
          blueprint_id: bp.id,
          name: bp.name,
          short_description: bp.short_description,
          long_description: bp.long_description,
          fixed: bp.fixed,
          proposed_slug: bp.id,
          expected_revision: current
        }

        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, fresh_draft)
         |> assign(:blueprint_commit_error, {:stale_revision, current})}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  # ────────────────────────────────────────────────────────────
  # Resolver task lifecycle
  # ────────────────────────────────────────────────────────────

  @doc """
  Feature 014 US1 / US3 — apply the resolver-task outcome to the
  appropriate draft assign. Caller has already cleared
  `:wizard_resolver_task` and `:wizard_input_locked`; this just
  populates the matching draft (or commit-error) and returns
  `{:noreply, socket}`.
  """
  def apply_resolver_outcome(socket, result) do
    case result do
      {:ok, {:draft_blueprint, fields}} ->
        slug = Slug.derive(fields.name)

        draft = %{
          name: fields.name,
          short_description: fields.short_description,
          long_description: fields.long_description,
          fixed: fields.fixed,
          proposed_slug: slug
        }

        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, draft)
         |> assign(:blueprint_commit_error, nil)}

      {:ok, {:freeform_object, fields}} ->
        draft = %{
          name: fields.name,
          short_description: fields.short_description,
          long_description: fields.long_description,
          fixed: fields.fixed
        }

        {:noreply,
         socket
         |> assign(:focused_object_draft, draft)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:last_spawn, nil)}

      {:error, message} ->
        {:noreply, assign(socket, :blueprint_commit_error, {:llm_refusal, message})}
    end
  end

  @doc """
  Feature 014 — cancel an in-flight wizard LLM resolver task on
  discard. Demonitors so the trailing `:DOWN` message is flushed;
  the completion message that arrives later will fail to match the
  `wizard_resolver_task: %{ref: ref}` guard and hit the generic
  stale-task fallback. Prevents a discarded draft from re-populating
  after the wizard thought they cancelled.
  """
  def cancel_resolver_task(%{assigns: %{wizard_resolver_task: %{ref: ref}}} = socket)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket
    |> assign(:wizard_resolver_task, nil)
    |> assign(:wizard_input_locked, false)
  end

  def cancel_resolver_task(socket), do: socket

  # ────────────────────────────────────────────────────────────
  # Live blueprint registry patching (US6)
  # ────────────────────────────────────────────────────────────

  @doc """
  Feature 014 US6 — apply a `WizardBlueprintRegistryChanged` payload
  to the wizard's `:object_blueprints` list in place. Insert (with
  de-dup) on `:created`; merge the sparse diff into the matching row
  on `:edited`.
  """
  def patch_blueprint_registry(socket, %{
        event: :created,
        blueprint_id: bp_id,
        revision: revision,
        payload: payload
      }) do
    list = socket.assigns[:object_blueprints] || []

    if Enum.any?(list, &(&1.id == bp_id)) do
      socket
    else
      # Build a real %ObjectBlueprint{} struct so the
      # :object_blueprints assign stays homogeneous (consumers can
      # pattern-match on the struct, access timestamps, etc.).
      # Timestamps are slightly off from the projector's canonical
      # values but within the same second.
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      row = %BlueprintRow{
        id: bp_id,
        kind: Map.get(payload, :kind, "object"),
        name: Map.get(payload, :name, ""),
        short_description: Map.get(payload, :short_description, ""),
        long_description: Map.get(payload, :long_description, ""),
        fixed: Map.get(payload, :fixed, false),
        revision: revision,
        inserted_at: now,
        updated_at: now
      }

      assign(
        socket,
        :object_blueprints,
        Enum.sort_by([row | list], &(&1.name || ""))
      )
    end
  end

  def patch_blueprint_registry(socket, %{
        event: :edited,
        blueprint_id: bp_id,
        revision: revision,
        payload: fields_changed
      }) do
    list = socket.assigns[:object_blueprints] || []

    updated =
      Enum.map(list, fn row ->
        if row.id == bp_id do
          Enum.reduce(fields_changed, row, fn {k, v}, acc -> Map.put(acc, k, v) end)
          |> Map.put(:revision, revision)
        else
          row
        end
      end)

    assign(socket, :object_blueprints, Enum.sort_by(updated, &(&1.name || "")))
  end
end
