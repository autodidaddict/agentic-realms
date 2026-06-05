defmodule AgenticRealmsWeb.GameComponents.WizardAuthoring do
  @moduledoc """
  Feature 014 — wizard authoring surface. Combines the sanctum
  (`authoring_mode == :blueprints`) and in-world (`:world`) views in a
  single component because the prompt textarea, the right-side panes,
  and the blueprint registry are all shared scaffolding — only the
  copy, the form rendered, and the commit handler differ.

  Private form helpers (`blueprint_draft_form`, `object_edit_form`,
  `object_draft_form`) wrap the four-field editor (name, [slug],
  short/long description, fixed) with the right form name and the
  right `phx-change` so the parent LiveView can keep its draft state
  in sync.

  `format_commit_error/1` translates the small closed set of error
  atoms the commit pipeline returns into human-readable copy. New
  errors must be added here, otherwise the catch-all clause falls
  through to `Refused: …`.
  """

  use AgenticRealmsWeb, :html

  alias AgenticRealms.World.Blueprint.Slug

  attr :authoring_mode, :atom, required: true
  attr :focused_blueprint_draft, :map, default: nil
  attr :focused_object_draft, :map, default: nil
  attr :focused_object_edit, :map, default: nil
  attr :object_blueprints, :list, required: true
  attr :room_objects, :list, default: []
  attr :wizard_prompt, :string, required: true
  attr :wizard_input_locked, :boolean, required: true
  attr :blueprint_commit_error, :any, default: nil
  attr :current_room_id, :string, default: nil
  attr :current_room_name, :string, default: nil
  attr :last_spawn, :map, default: nil
  attr :tweaks, :map, required: true

  def wizard_authoring_view(assigns) do
    ~H"""
    <div class="wizard">
      <div class="w-left">
        <div class="w-head">
          <div>
            <div class="lbl">Wizard mode · creator</div>
            <div class="title">
              <%= if @authoring_mode == :blueprints do %>
                In the <b>sanctum</b>
              <% else %>
                Standing in <b>{@current_room_name || "the world"}</b>
              <% end %>
            </div>
          </div>
          <button
            type="button"
            class="btn-ghost"
            phx-click="toggle_authoring_mode"
            data-testid="authoring-mode-toggle"
          >
            <%= if @authoring_mode == :blueprints do %>
              Return to your body
            <% else %>
              Enter trance
            <% end %>
          </button>
        </div>

        <%= if @authoring_mode == :blueprints do %>
          <div class="w-input-wrap">
            <div class="w-prompt-label">
              <span class="hint">
                Describe an object archetype — the model extracts its name, descriptions, and fixed flag onto the form. Refine and commit.
              </span>
            </div>
            <form phx-submit="submit_wizard_prompt" phx-change="update_wizard_prompt">
              <textarea
                name="text"
                class="w-input"
                placeholder="A brass-bound chest, weather-beaten, with the seal of the Western Reach…"
                spellcheck="false"
                disabled={@wizard_input_locked}
              >{@wizard_prompt}</textarea>
              <div style="font-size: 11px; color: var(--ink-faint); display: flex; gap: 18px; margin-top: 8px;">
                <%= if @wizard_input_locked do %>
                  <span class="pulse">extracting…</span>
                <% end %>
                <button
                  type="submit"
                  class="btn-ghost"
                  style="margin-left: auto;"
                  disabled={@wizard_input_locked}
                >
                  Extract
                </button>
              </div>
            </form>
            <%= if is_nil(@focused_blueprint_draft) and match?({:llm_refusal, _}, @blueprint_commit_error) do %>
              <div class="bp-refusal" data-testid="wizard-prompt-refusal">
                {elem(@blueprint_commit_error, 1)}
              </div>
            <% end %>
          </div>

          <%= if @focused_blueprint_draft do %>
            <div class="w-footer">
              <div class="meta">
                <%= if rev = Map.get(@focused_blueprint_draft, :expected_revision) do %>
                  <span>editing · rev {rev}</span>
                <% else %>
                  <span>draft · rev 1</span>
                <% end %>
              </div>
              <div class="actions">
                <button type="button" class="btn-ghost" phx-click="discard_blueprint_draft">
                  Discard
                </button>
                <button type="button" class="btn-primary" phx-click="commit_blueprint_draft">
                  Save Blueprint
                </button>
              </div>
            </div>
          <% end %>
        <% else %>
          <div class="w-input-wrap">
            <div class="w-prompt-label">
              <span class="hint">
                Describe a one-off object to manifest into <strong>{@current_room_name || "your current room"}</strong>,
                or click <strong>Spawn here</strong> on any blueprint to drop a copy in.
              </span>
            </div>
            <form phx-submit="submit_wizard_prompt" phx-change="update_wizard_prompt">
              <textarea
                name="text"
                class="w-input"
                placeholder="A small clay pot, half-empty of dry barley, leaning against the wall…"
                spellcheck="false"
                disabled={@wizard_input_locked}
              >{@wizard_prompt}</textarea>
              <div style="font-size: 11px; color: var(--ink-faint); display: flex; gap: 18px; margin-top: 8px;">
                <%= if @wizard_input_locked do %>
                  <span class="pulse">extracting…</span>
                <% end %>
                <button
                  type="submit"
                  class="btn-ghost"
                  style="margin-left: auto;"
                  disabled={@wizard_input_locked}
                >
                  Extract
                </button>
              </div>
            </form>
            <%= if is_nil(@focused_object_draft) and match?({:llm_refusal, _}, @blueprint_commit_error) do %>
              <div class="bp-refusal" data-testid="wizard-prompt-refusal">
                {elem(@blueprint_commit_error, 1)}
              </div>
            <% end %>
          </div>

          <%= if @focused_object_draft do %>
            <div class="w-footer">
              <div class="meta">
                <span>one-off · this room</span>
              </div>
              <div class="actions">
                <button type="button" class="btn-ghost" phx-click="discard_object_draft">
                  Discard
                </button>
                <button type="button" class="btn-primary" phx-click="commit_object_draft">
                  Spawn
                </button>
              </div>
            </div>
          <% end %>

          <%= if @last_spawn do %>
            <div
              class="bp-spawn-toast"
              data-testid="spawn-confirmation"
              role="status"
              aria-live="polite"
              style="margin: 14px 0 0 0;"
            >
              <span class="bp-spawn-toast__check" aria-hidden="true">✓</span>
              <div class="bp-spawn-toast__body">
                <div>
                  Spawned <strong>{@last_spawn.name || @last_spawn.blueprint_id}</strong>
                  <%= if @last_spawn.room_name do %>
                    in <strong>{@last_spawn.room_name}</strong>
                  <% end %>
                </div>
                <div class="bp-spawn-toast__meta">
                  Witnesses in this room saw it appear.
                </div>
              </div>
              <button
                type="button"
                class="bp-spawn-toast__close"
                phx-click="dismiss_last_spawn"
                aria-label="Dismiss"
              >
                ×
              </button>
            </div>
          <% end %>
          <%= if @blueprint_commit_error && not match?({:llm_refusal, _}, @blueprint_commit_error) do %>
            <div class="bp-error" data-testid="world-spawn-error" style="margin-top: 14px;">
              {format_commit_error(@blueprint_commit_error)}
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="w-right">
        <%= if @authoring_mode == :blueprints and @focused_blueprint_draft do %>
          <section class="w-pane">
            <div class="w-pane-head">
              <div class="lbl">Interpreted data</div>
            </div>
            <div class="w-pane-body">
              <.blueprint_draft_form
                draft={@focused_blueprint_draft}
                commit_error={@blueprint_commit_error}
              />
            </div>
          </section>
        <% end %>

        <%= if @authoring_mode == :world and @focused_object_draft do %>
          <section class="w-pane">
            <div class="w-pane-head">
              <div class="lbl">Interpreted data · one-off Object</div>
            </div>
            <div class="w-pane-body">
              <.object_draft_form
                draft={@focused_object_draft}
                commit_error={@blueprint_commit_error}
              />
            </div>
          </section>
        <% end %>

        <%= if @authoring_mode == :world and @focused_object_edit do %>
          <section class="w-pane">
            <div class="w-pane-head">
              <div class="lbl">Edit Object · in this room</div>
              <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.08em; text-transform: uppercase;">
                in-place
              </div>
            </div>
            <div class="w-pane-body">
              <.object_edit_form
                edit={@focused_object_edit}
                commit_error={@blueprint_commit_error}
              />
              <div class="w-footer" style="margin-top: 12px;">
                <div class="meta">
                  <span>{@focused_object_edit.object_id}</span>
                </div>
                <div class="actions">
                  <button type="button" class="btn-ghost" phx-click="discard_object_edit">
                    Discard
                  </button>
                  <button type="button" class="btn-primary" phx-click="commit_object_edit">
                    Commit
                  </button>
                </div>
              </div>
            </div>
          </section>
        <% end %>

        <%= if @authoring_mode == :world do %>
          <section class="w-pane">
            <div class="w-pane-head">
              <div class="lbl">Things in <b>{@current_room_name || "this room"}</b></div>
              <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.08em; text-transform: uppercase;">
                {length(@room_objects)} present
              </div>
            </div>
            <div class="w-pane-body" data-testid="room-objects-panel">
              <%= if @room_objects == [] do %>
                <div class="empty-preview">
                  <div>
                    <div class="title">No objects here yet</div>
                    <div>
                      Manifest something with a prompt, or <strong>Spawn here</strong>
                      from the registry.
                    </div>
                  </div>
                </div>
              <% else %>
                <ul class="blueprint-list" style="list-style: none; padding: 0; margin: 0;">
                  <li
                    :for={obj <- @room_objects}
                    class="blueprint-row"
                    data-object-id={obj.id}
                    style="border-bottom: 1px solid var(--rule); padding: 8px 12px;"
                  >
                    <div style="display: flex; align-items: baseline; gap: 8px;">
                      <strong>{obj.name}</strong>
                      <%= if obj.fixed do %>
                        <span style="color: var(--ink-faint); font-size: 11px;">fixed</span>
                      <% end %>
                      <button
                        type="button"
                        class="btn-ghost"
                        style="margin-left: auto; font-size: 11px; padding: 2px 8px;"
                        phx-click="focus_object_for_edit"
                        phx-value-object_id={obj.id}
                        data-testid={"edit-object-#{obj.id}"}
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        class="btn-ghost"
                        style="font-size: 11px; padding: 2px 8px;"
                        phx-click="extract_essence"
                        phx-value-object_id={obj.id}
                        data-testid={"extract-essence-#{obj.id}"}
                      >
                        Extract essence
                      </button>
                    </div>
                    <div style="color: var(--ink-faint); font-size: 12px;">
                      {obj.short_description}
                    </div>
                  </li>
                </ul>
              <% end %>
            </div>
          </section>
        <% end %>

        <section class="w-pane">
          <div class="w-pane-head">
            <div class="lbl">Blueprints</div>
            <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.08em; text-transform: uppercase;">
              {length(@object_blueprints)} authored
            </div>
          </div>
          <div class="w-pane-body" data-testid="blueprints-registry">
            <%= if @object_blueprints == [] do %>
              <div class="empty-preview">
                <div>
                  <div class="title">Nothing in the registry yet</div>
                  <div>
                    Commit a draft to populate the registry.
                  </div>
                </div>
              </div>
            <% else %>
              <ul class="blueprint-list" style="list-style: none; padding: 0; margin: 0;">
                <li
                  :for={bp <- @object_blueprints}
                  class="blueprint-row"
                  data-blueprint-id={bp.id}
                  style="border-bottom: 1px solid var(--rule); padding: 8px 12px;"
                >
                  <div style="display: flex; align-items: baseline; gap: 8px;">
                    <button
                      type="button"
                      class="bp-link"
                      phx-click="focus_blueprint"
                      phx-value-blueprint_id={bp.id}
                      data-testid={"focus-blueprint-#{bp.id}"}
                      title="Edit this blueprint"
                    >
                      <strong>{bp.name}</strong>
                      <span style="color: var(--ink-faint); font-size: 11px;">
                        {bp.id} · rev {bp.revision}
                      </span>
                    </button>
                    <%= if @authoring_mode == :world and @current_room_id do %>
                      <button
                        type="button"
                        class="btn-ghost"
                        style="margin-left: auto; font-size: 11px; padding: 2px 8px;"
                        phx-click="spawn_here"
                        phx-value-blueprint_id={bp.id}
                        data-testid={"spawn-here-#{bp.id}"}
                      >
                        Spawn here
                      </button>
                    <% end %>
                  </div>
                  <div style="color: var(--ink-faint); font-size: 12px;">
                    {bp.short_description}
                  </div>
                </li>
              </ul>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :draft, :map, required: true
  attr :commit_error, :any, default: nil

  defp blueprint_draft_form(assigns) do
    ~H"""
    <form phx-change="update_blueprint_draft">
      <div class="bp-field">
        <label class="bp-field-label">
          Name <span class="bp-field-hint">click any field to edit</span>
        </label>
        <input
          type="text"
          name="draft[name]"
          value={@draft.name}
          class="bp-input"
        />
      </div>

      <div class="bp-field">
        <label class="bp-field-label">
          Slug
          <span class="bp-field-hint">
            {slug_hint(@draft)}
          </span>
        </label>
        <input
          type="text"
          name="draft[proposed_slug]"
          value={@draft.proposed_slug}
          class="bp-input bp-input--mono"
          readonly={not is_nil(Map.get(@draft, :expected_revision))}
          data-testid="blueprint-slug"
        />
      </div>

      <div class="bp-field">
        <label class="bp-field-label">Short description</label>
        <input
          type="text"
          name="draft[short_description]"
          value={@draft.short_description}
          class="bp-input"
        />
      </div>

      <div class="bp-field">
        <label class="bp-field-label">Long description</label>
        <textarea
          name="draft[long_description]"
          rows="5"
          class="bp-input bp-input--multiline"
        >{@draft.long_description}</textarea>
      </div>

      <div class="bp-field">
        <label class="bp-fixed-toggle">
          <input
            type="hidden"
            name="draft[fixed]"
            value="false"
          />
          <input
            type="checkbox"
            name="draft[fixed]"
            value="true"
            checked={@draft.fixed}
          /> Fixed (cannot be picked up)
        </label>
      </div>

      <%= if @commit_error do %>
        <div class="bp-error" data-testid="blueprint-commit-error">
          {format_commit_error(@commit_error)}
        </div>
      <% end %>
    </form>
    """
  end

  attr :edit, :map, required: true
  attr :commit_error, :any, default: nil

  defp object_edit_form(assigns) do
    ~H"""
    <form phx-change="update_object_edit">
      <div class="bp-field">
        <label class="bp-field-label">
          Name <span class="bp-field-hint">click any field to edit</span>
        </label>
        <input type="text" name="edit[name]" value={@edit.name} class="bp-input" />
      </div>
      <div class="bp-field">
        <label class="bp-field-label">Short description</label>
        <input
          type="text"
          name="edit[short_description]"
          value={@edit.short_description}
          class="bp-input"
        />
      </div>
      <div class="bp-field">
        <label class="bp-field-label">Long description</label>
        <textarea
          name="edit[long_description]"
          rows="5"
          class="bp-input bp-input--multiline"
        >{@edit.long_description}</textarea>
      </div>
      <div class="bp-field">
        <label class="bp-fixed-toggle">
          <input type="hidden" name="edit[fixed]" value="false" />
          <input type="checkbox" name="edit[fixed]" value="true" checked={@edit.fixed} />
          Fixed (cannot be picked up)
        </label>
      </div>
      <%= if @commit_error do %>
        <div class="bp-error" data-testid="object-edit-commit-error">
          {format_commit_error(@commit_error)}
        </div>
      <% end %>
    </form>
    """
  end

  attr :draft, :map, required: true
  attr :commit_error, :any, default: nil

  defp object_draft_form(assigns) do
    ~H"""
    <form phx-change="update_object_draft">
      <div class="bp-field">
        <label class="bp-field-label">
          Name <span class="bp-field-hint">click any field to edit</span>
        </label>
        <input type="text" name="draft[name]" value={@draft.name} class="bp-input" />
      </div>

      <div class="bp-field">
        <label class="bp-field-label">Short description</label>
        <input
          type="text"
          name="draft[short_description]"
          value={@draft.short_description}
          class="bp-input"
        />
      </div>

      <div class="bp-field">
        <label class="bp-field-label">Long description</label>
        <textarea
          name="draft[long_description]"
          rows="5"
          class="bp-input bp-input--multiline"
        >{@draft.long_description}</textarea>
      </div>

      <div class="bp-field">
        <label class="bp-fixed-toggle">
          <input type="hidden" name="draft[fixed]" value="false" />
          <input type="checkbox" name="draft[fixed]" value="true" checked={@draft.fixed} />
          Fixed (cannot be picked up)
        </label>
      </div>

      <%= if @commit_error do %>
        <div class="bp-error" data-testid="object-commit-error">
          {format_commit_error(@commit_error)}
        </div>
      <% end %>
    </form>
    """
  end

  # Slug field hint — distinguishes locked (edit mode), auto-derived
  # (slug == Slug.derive(name)), and manual (slug differs from what
  # derive would produce). No sticky flag — the slug value itself is
  # the source of truth.
  defp slug_hint(draft) do
    cond do
      not is_nil(Map.get(draft, :expected_revision)) ->
        "locked after creation"

      Map.get(draft, :proposed_slug, "") ==
          Slug.derive(Map.get(draft, :name, "")) ->
        "auto from name"

      true ->
        "manual"
    end
  end

  defp format_commit_error(:not_a_wizard), do: "Not authorized."
  defp format_commit_error(:unknown_player), do: "Account no longer exists."

  defp format_commit_error(:invalid_slug),
    do: "Slug must be lowercase letters, digits, and underscores; 1–64 characters."

  defp format_commit_error(:invalid_field),
    do: "That field can't be edited from here."

  defp format_commit_error(:slug_already_exists),
    do: "A blueprint with that slug already exists. Choose a different slug."

  defp format_commit_error(:name_required), do: "Name is required."
  defp format_commit_error(:short_description_required), do: "Short description is required."
  defp format_commit_error(:long_description_required), do: "Long description is required."
  defp format_commit_error(:unknown_blueprint), do: "That blueprint no longer exists."
  defp format_commit_error(:unknown_object), do: "That object no longer exists."

  defp format_commit_error(:object_not_in_room),
    do: "That object isn't in this room anymore."

  defp format_commit_error(:object_not_editable_here),
    do: "That object isn't in this room anymore — someone just picked it up, or you've moved on."

  defp format_commit_error(:blueprint_already_exists),
    do: "Another wizard just created a blueprint with that slug. Choose a different slug."

  defp format_commit_error(:blueprint_not_found),
    do: "That blueprint no longer exists."

  defp format_commit_error(:room_not_found),
    do: "That room isn't available right now — try again in a moment."

  defp format_commit_error({:llm_refusal, message}), do: message

  defp format_commit_error({:stale_revision, current}),
    do:
      "Another wizard edited this blueprint while you were working (now at rev #{current}). " <>
        "Your form has been reloaded with the latest values; reapply your changes and commit again."

  defp format_commit_error(other), do: "Refused: #{inspect(other)}."
end
