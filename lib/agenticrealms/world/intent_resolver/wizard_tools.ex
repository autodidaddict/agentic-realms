defmodule AgenticRealms.World.IntentResolver.WizardTools do
  @moduledoc """
  Feature 014 — Anthropic tool schemas exposed to wizards. Separate from
  the player-facing `Tools` module because the wizard's tool surface is
  intentionally narrow per FR-022 / FR-024 / FR-025 — creation verbs
  only, no edit verbs, mode-dependent.

  Milestone 1 ships `:blueprints` mode tools only:
    * `draft_object_blueprint` — produces a draft (NOT a dispatched
      command). The LiveView populates the Interpreted Data card with
      the result and the wizard refines + commits via form.
    * `refuse` — the standard escape hatch when the prompt is not an
      object-archetype description.

  World-mode tools (`manifest_object_freeform`, `spawn_object_from_blueprint`)
  arrive in US2 / US3.

  See `specs/014-item-blueprints/contracts/intent_tools.md`.
  """

  @doc "Set of recognized tool names in :blueprints mode."
  @spec names_blueprints() :: MapSet.t(String.t())
  def names_blueprints, do: MapSet.new(~w(draft_object_blueprint refuse))

  @doc "Set of recognized tool names in :world mode (wizard-only)."
  @spec names_world() :: MapSet.t(String.t())
  def names_world, do: MapSet.new(~w(manifest_object_freeform refuse))

  @doc "Tool definitions for :blueprints mode, in wire order."
  @spec list_blueprints() :: [map()]
  def list_blueprints do
    [
      %{
        "name" => "draft_object_blueprint",
        "description" =>
          "Extract fields for a new reusable object archetype (blueprint) the wizard is authoring. Use when the wizard describes a kind of object meant to be cloned into the world later (e.g., 'a brass-bound chest with the seal of the Western Reach', 'a small clay pot half-empty of barley'). Do NOT use to describe a one-off object placed in a specific room; that's a different (world-mode) tool not yet exposed.",
        "input_schema" => %{
          "type" => "object",
          "required" => ["name", "short_description", "long_description"],
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" =>
                "Short, lowercase noun phrase (1–4 words) — e.g., 'brass-bound chest', 'clay pot'."
            },
            "short_description" => %{
              "type" => "string",
              "description" =>
                "A short noun phrase WITH an indefinite article, all lowercase, NO trailing period, ≤ 40 chars (e.g., 'a brass-bound chest', 'a small clay pot', 'an iron lantern'). This is the one-line text shown in 'Also here:' room listings; it MUST read naturally inside a sentence and MUST NOT contain multiple clauses or end with punctuation."
            },
            "long_description" => %{
              "type" => "string",
              "description" =>
                "Multi-sentence prose shown when a player examines an instance. Expand on the short description with material, condition, markings, etc."
            },
            "fixed" => %{
              "type" => "boolean",
              "description" =>
                "True if instances of this archetype cannot be picked up (furniture, embedded fixtures, monuments). Default false."
            }
          }
        }
      },
      refuse_tool(
        "Decline to draft a blueprint because the wizard's prompt does not describe an object archetype. Use when: the prompt asks a question, describes a place or NPC, asks to edit something existing (edits happen via the form, not via prompts), or is otherwise off-task. `message` is the wizard-facing refusal."
      )
    ]
  end

  @doc "Tool definitions for :world mode, in wire order."
  @spec list_world() :: [map()]
  def list_world do
    [
      %{
        "name" => "manifest_object_freeform",
        "description" =>
          "Extract fields for a single one-off Object the wizard is manifesting directly into their current room — NOT a reusable archetype. Use when the wizard describes a specific concrete thing they want to put into the world right now (e.g., 'a small clay pot, half-empty of dry barley, leaning against the wall'). The Object lands in the wizard's current room with no Blueprint involvement.",
        "input_schema" => %{
          "type" => "object",
          "required" => ["name", "short_description", "long_description"],
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" =>
                "Short, lowercase noun phrase (1–4 words) — e.g., 'clay pot', 'iron lantern'. No leading article."
            },
            "short_description" => %{
              "type" => "string",
              "description" =>
                "A short noun phrase WITH an indefinite article, all lowercase, NO trailing period, ≤ 40 chars (e.g., 'a small clay pot', 'an iron lantern'). This is the one-line text shown in 'Also here:' room listings."
            },
            "long_description" => %{
              "type" => "string",
              "description" =>
                "Multi-sentence prose shown when a player examines the Object. Expand on the short description with material, condition, markings, etc."
            },
            "fixed" => %{
              "type" => "boolean",
              "description" =>
                "True if the Object cannot be picked up (furniture, embedded fixtures, monuments). Default false."
            }
          }
        }
      },
      refuse_tool(
        "Decline to manifest an Object because the wizard's prompt does not describe one. Use when: the prompt asks a question, describes a place or NPC, asks to edit something existing (edits happen via the form, not via prompts), or is otherwise off-task. `message` is the wizard-facing refusal."
      )
    ]
  end

  defp refuse_tool(description) do
    %{
      "name" => "refuse",
      "description" => description,
      "input_schema" => %{
        "type" => "object",
        "required" => ["message"],
        "properties" => %{
          "message" => %{
            "type" => "string",
            "description" =>
              "Brief, friendly explanation of why no draft was extracted. Hint at what to try."
          }
        }
      }
    }
  end
end
