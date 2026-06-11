defmodule AgenticRealms.World.IntentResolver.WizardTools do
  @moduledoc """
  Feature 014 — Anthropic tool schemas exposed to wizards. Separate from
  the player-facing `Tools` module because the wizard's tool surface is
  intentionally narrow per FR-022 / FR-024 / FR-025 — creation verbs
  only, no edit verbs, mode-dependent.

  `:blueprints` mode (authoring archetypes) tools:
    * `draft_object_blueprint` / `draft_npc_blueprint` — produce a draft
      (NOT a dispatched command). The LiveView populates the Interpreted
      Data card and the wizard refines + commits via form. The model picks
      the npc tool for a character/creature, the object tool otherwise.
    * `list_behavior_groups` (feature 015) — a read tool returning the named
      behavior groups, so `draft_npc_blueprint` behavior_group proposals are
      grounded in real registered names (FR-020a). Unknown names are
      dropped before commit (FR-018).
    * `refuse` — the escape hatch when the prompt is not an archetype.

  `:world` mode (manifesting one-offs) tools: `manifest_object_freeform`
  (feature 014), `manifest_npc_freeform` (feature 015 US5), `refuse`.

  See `specs/014-item-blueprints/contracts/intent_tools.md` and
  `specs/015-npc-blueprints/`.
  """

  @doc "Set of recognized tool names in :blueprints mode."
  @spec names_blueprints() :: MapSet.t(String.t())
  def names_blueprints,
    do: MapSet.new(~w(draft_object_blueprint draft_npc_blueprint list_behavior_groups refuse))

  @doc "Set of recognized tool names in :world mode (wizard-only)."
  @spec names_world() :: MapSet.t(String.t())
  def names_world, do: MapSet.new(~w(manifest_object_freeform manifest_npc_freeform refuse))

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
      %{
        "name" => "draft_npc_blueprint",
        "description" =>
          "Extract fields for a new reusable NPC archetype (blueprint) the wizard is authoring — a character, creature, or person meant to be spawned into the world later (e.g., 'Garrick, a gruff but kind innkeeper', 'a hulking cave troll that hates sunlight'). Use when the prompt describes a living / sentient / animate being. Do NOT use for inanimate objects — that's `draft_object_blueprint`. You MAY call `list_behavior_groups` first to ground any behavior_groups you propose.",
        "input_schema" => %{
          "type" => "object",
          "required" => ["name", "short_description", "long_description"],
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" =>
                "The NPC's name or short descriptor — a proper name keeps its capitalization, otherwise a lowercase noun phrase (e.g., 'Garrick', 'cave troll')."
            },
            "short_description" => %{
              "type" => "string",
              "description" =>
                "A short noun phrase WITH an indefinite article (or the bare proper name), NO trailing period, ≤ 60 chars. Shown in 'Also here:' room listings (e.g., 'a gruff innkeeper', 'a hulking cave troll')."
            },
            "long_description" => %{
              "type" => "string",
              "description" =>
                "Multi-sentence prose shown when a player examines the NPC — appearance, bearing, notable features."
            },
            "lore" => %{
              "type" => "string",
              "description" =>
                "Private backstory and personality that grounds how the NPC converses. NOT shown verbatim to players; it informs in-character chat replies."
            },
            "fixed" => %{
              "type" => "boolean",
              "description" =>
                "True only if the NPC cannot be moved or relocated (rare). Default false."
            },
            "behavior_groups" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" =>
                "Names of behavior groups (\"behavior_groups\") to attach, chosen ONLY from the list returned by `list_behavior_groups`. Omit or leave empty if none fit. Never invent names."
            }
          }
        }
      },
      %{
        "name" => "list_behavior_groups",
        "description" =>
          "List the named behavior groups (\"behavior_groups\") available to attach to an NPC blueprint, with their descriptions. Call this BEFORE `draft_npc_blueprint` whenever you intend to propose behavior_groups, so your proposals reference real registered names.",
        "input_schema" => %{"type" => "object", "properties" => %{}}
      },
      refuse_tool(
        "Decline to draft a blueprint because the wizard's prompt does not describe an object or NPC archetype. Use when: the prompt asks a question, describes a place / room, asks to edit something existing (edits happen via the form, not via prompts), or is otherwise off-task. `message` is the wizard-facing refusal."
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
      %{
        "name" => "manifest_npc_freeform",
        "description" =>
          "Extract fields for a single one-off NPC the wizard is manifesting directly into their current room — NOT a reusable archetype. Use when the wizard describes a specific character/creature/person they want to exist in the world right now (e.g., 'a nervous courier catching his breath by the door'). The NPC lands in the wizard's current room with no Blueprint involvement.",
        "input_schema" => %{
          "type" => "object",
          "required" => ["name", "short_description", "long_description"],
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" =>
                "The NPC's name or short descriptor — a proper name keeps its capitalization, otherwise a lowercase noun phrase (e.g., 'a nervous courier')."
            },
            "short_description" => %{
              "type" => "string",
              "description" =>
                "A short noun phrase WITH an indefinite article (or the bare proper name), NO trailing period, ≤ 60 chars. Shown in 'Also here:' room listings."
            },
            "long_description" => %{
              "type" => "string",
              "description" => "Multi-sentence prose shown when a player examines the NPC."
            },
            "lore" => %{
              "type" => "string",
              "description" =>
                "Private backstory and personality grounding the NPC's conversation. Not shown verbatim to players."
            },
            "fixed" => %{
              "type" => "boolean",
              "description" => "True only if the NPC cannot be moved (rare). Default false."
            }
          }
        }
      },
      refuse_tool(
        "Decline to manifest anything because the wizard's prompt does not describe a concrete one-off object or NPC. Use when: the prompt asks a question, describes a place / room, asks to edit something existing (edits happen via the form, not via prompts), or is otherwise off-task. `message` is the wizard-facing refusal."
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
