defmodule AgenticRealmsWeb.GameComponents.CharacterCreation do
  @moduledoc """
  Feature 021 — the character creation dialog.

  Shown once, before a player has ever entered the world, and there is no way
  out of it except creating a character or leaving the page: the shared modal
  shell is rendered with `dismissable={false}`, so it carries no close button,
  no click-catching backdrop, and no Escape binding.

  Every option it offers comes from the SRD content library. The component holds
  no list of species, classes, backgrounds, skills, or feats, and no rules prose
  of its own — the names, the trait text, and the numbers are all read from
  `Srd.Content` and `Srd.Character`.

  Steps arrive one per user story, and the strip renders from the ones that have
  shipped rather than from a hardcoded five. Until a step exists,
  `AgenticRealms.World.CharacterGen.complete/1` makes its choices.
  """

  use AgenticRealmsWeb, :html

  import AgenticRealmsWeb.GameComponents.Primitives, only: [modal: 1, signed: 1]
  import AgenticRealmsWeb.GameComponents.PlayerModals, only: [main_panel: 1, abilities_panel: 1]

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias AgenticRealms.World.CharacterGen
  alias Srd.Content.Backgrounds
  alias Srd.Content.Classes
  alias Srd.Content.Feats
  alias Srd.Content.Items
  alias Srd.Content.Species
  alias Srd.Content.Weapons
  alias Srd.Rules.Ability
  alias Srd.Rules.Skill

  # The steps that have shipped, in order. Adding one here is what makes a later
  # user story visible; the strip, the gating, and the footer all read this.
  @shipped [:identity, :abilities, :skills, :specializations, :review]

  attr :draft, :map, required: true

  def character_creation_modal(assigns) do
    assigns = assign(assigns, :steps, @shipped)

    ~H"""
    <.modal title="Create Your Character" glyph="✧" dismissable={false}>
      <div class="cc-steps" role="tablist" aria-label="Character creation steps">
        <.step_tab
          :for={{step, index} <- Enum.with_index(@steps, 1)}
          step={step}
          index={index}
          draft={@draft}
        />
      </div>

      <.error_list errors={@draft.errors} />

      <div class="cc-panel">
        <.identity_step :if={@draft.step == :identity} draft={@draft} />
        <.abilities_step :if={@draft.step == :abilities} draft={@draft} />
        <.skills_step :if={@draft.step == :skills} draft={@draft} />
        <.specializations_step :if={@draft.step == :specializations} draft={@draft} />
        <.review_step :if={@draft.step == :review} draft={@draft} />
      </div>

      <.footer draft={@draft} steps={@steps} />
    </.modal>
    """
  end

  attr :step, :atom, required: true
  attr :index, :integer, required: true
  attr :draft, :map, required: true

  defp step_tab(assigns) do
    ~H"""
    <button
      class={[
        "cc-step",
        @draft.step == @step && "active",
        Draft.complete?(@draft, @step) && "done"
      ]}
      type="button"
      role="tab"
      aria-selected={to_string(@draft.step == @step)}
      disabled={not Draft.reachable?(@draft, @step)}
      phx-click="creation_step"
      phx-value-step={@step}
    >
      <span class="cc-step-index">{@index}</span>
      <span>{step_label(@step)}</span>
    </button>
    """
  end

  defp step_label(:identity), do: "Identity"
  defp step_label(:abilities), do: "Abilities"
  defp step_label(:skills), do: "Skills"
  defp step_label(:specializations), do: "Specializations"
  defp step_label(:review), do: "Review"

  attr :errors, :list, required: true

  defp error_list(assigns) do
    ~H"""
    <ul :if={@errors != []} class="cc-errors">
      <li :for={{_field, message} <- @errors}>{message}</li>
    </ul>
    """
  end

  # --- Identity -------------------------------------------------------------

  attr :draft, :map, required: true

  defp identity_step(assigns) do
    ~H"""
    <div class="cc-field">
      <label class="cc-label" for="cc-name">Name</label>
      <input
        id="cc-name"
        class="cc-input"
        type="text"
        name="name"
        value={@draft.name}
        maxlength="32"
        autocomplete="off"
        placeholder="What are you called?"
        phx-keyup="creation_name"
        phx-debounce="400"
      />
      <p class={["cc-hint", name_hint_class(@draft.name_status)]}>
        {name_hint(@draft.name_status)}
      </p>
    </div>

    <.option_group
      title="Species"
      field="species"
      selected={@draft.species_slug}
      options={
        Enum.map(Species.all(), fn species ->
          %{
            slug: species.slug,
            name: species.name,
            meta: "#{sizes(species.sizes)} · #{species.speed} ft.",
            traits: Enum.map(species.features, & &1.name)
          }
        end)
      }
    />

    <.option_group
      title="Class"
      field="class"
      selected={@draft.class_slug}
      options={
        Enum.map(Classes.all(), fn class ->
          %{
            slug: class.slug,
            name: class.name,
            meta:
              "Hit die #{hit_die(class.hit_die)} · " <>
                "#{primary(class.primary_ability)} · saves #{abilities(class.saving_throws)}",
            traits: level_one_features(class)
          }
        end)
      }
    />

    <.option_group
      title="Background"
      field="background"
      selected={@draft.background_slug}
      options={
        Enum.map(Backgrounds.all(), fn background ->
          %{
            slug: background.slug,
            name: background.name,
            meta:
              "Raises #{abilities(background.ability_scores)} · " <>
                "#{feat_name(background.origin_feat)}",
            traits: Enum.map(background.skills, &Skill.name/1)
          }
        end)
      }
    />

    <p :if={@draft.class_slug} class="cc-deferred">
      {deferred_note(@draft.class_slug)}
    </p>
    """
  end

  # --- Abilities ------------------------------------------------------------

  attr :draft, :map, required: true

  defp abilities_step(assigns) do
    assigns =
      assigns
      |> assign(:scores, Draft.scores(assigns.draft))
      |> assign(:increases, Draft.increases(assigns.draft))
      |> assign(:offered, Draft.raisable_abilities(assigns.draft))
      |> assign(:array, Ability.standard_array())

    ~H"""
    <p class="cc-lead">
      The standard array, spread across the six abilities. Each score is used
      once; assigning one an ability already holds swaps the two.
    </p>

    <div class="cc-abilities">
      <div :for={ability <- Ability.all()} class="cc-ability">
        <div class="cc-ability-head">
          <span class="cc-ability-name">{Ability.name(ability)}</span>
          <span class="cc-ability-total">
            <span class="cc-ability-score">{Map.get(@scores, ability, "—")}</span>
            <span :if={Map.get(@scores, ability)} class="cc-ability-mod">
              {signed(Srd.Rules.Ability.modifier(Map.fetch!(@scores, ability)))}
            </span>
            <span :if={Map.get(@increases, ability)} class="cc-ability-bump">
              {signed(Map.fetch!(@increases, ability))} from background
            </span>
          </span>
        </div>
        <div class="cc-array">
          <button
            :for={value <- @array}
            class={["cc-array-value", @draft.array[ability] == value && "selected"]}
            type="button"
            aria-pressed={to_string(@draft.array[ability] == value)}
            phx-click="creation_assign_ability"
            phx-value-ability={ability}
            phx-value-value={value}
          >
            {value}
          </button>
        </div>
      </div>
    </div>

    <fieldset class="cc-group">
      <legend class="cc-label">Background Increases</legend>
      <p class="cc-lead">
        {background_increase_note(@draft, @offered)}
      </p>
      <div class="cc-spreads">
        <button
          :for={{value, label} <- spread_options(@offered)}
          class={["cc-spread", spread_param(@draft) == value && "selected"]}
          type="button"
          aria-pressed={to_string(spread_param(@draft) == value)}
          phx-click="creation_spread"
          phx-value-spread={value}
        >
          {label}
        </button>
      </div>
    </fieldset>
    """
  end

  defp background_increase_note(%{background_slug: nil}, _offered),
    do: "Choose a background first — it decides which abilities you may raise."

  defp background_increase_note(_draft, offered),
    do: "Your background raises #{abilities(offered)}. Take +2 and +1, or +1 to all three."

  # Every legal spread as a flat list of buttons: the three-way even split, then
  # each ordered pair for the +2/+1 form. Six options at most, which is fewer
  # than a two-step picker would cost the player.
  defp spread_options([]), do: []

  defp spread_options(offered) do
    even = {"even", "+1 to all three"}

    splits =
      for larger <- offered, smaller <- offered, larger != smaller do
        {"split:#{larger}:#{smaller}", "+2 #{Ability.name(larger)}, +1 #{Ability.name(smaller)}"}
      end

    [even | splits]
  end

  defp spread_param(%{spread: nil}), do: nil
  defp spread_param(%{spread: {:even, _}}), do: "even"
  defp spread_param(%{spread: {:split, larger, smaller}}), do: "split:#{larger}:#{smaller}"

  # --- Skills ---------------------------------------------------------------

  attr :draft, :map, required: true

  defp skills_step(assigns) do
    assigns =
      assigns
      |> assign(:granted, Draft.grants(assigns.draft).skills)
      |> assign(:offered, Draft.offered_skills(assigns.draft))
      |> assign(:allowance, Draft.skill_allowance(assigns.draft))
      |> assign(:picked, assigns.draft.skill_picks)

    ~H"""
    <div :if={@granted != []} class="cc-field">
      <span class="cc-label">Already Yours</span>
      <p class="cc-lead">
        Your background and species grant these outright, so they cost you
        nothing here.
      </p>
      <div class="cc-skills">
        <div :for={skill <- @granted} class="cc-skill held">
          <span class="cc-skill-name">{Skill.name(skill)}</span>
          <span class="cc-skill-meta">
            {ability_abbrev(skill)} {modifier_label(@draft, skill, true)}
          </span>
          <span class="cc-skill-note">granted</span>
        </div>
      </div>
    </div>

    <fieldset class="cc-group">
      <legend class="cc-label">
        Choose {@allowance} {pluralize("Skill", @allowance)}
      </legend>
      <p class="cc-lead">{skill_note(@draft, @picked, @allowance)}</p>
      <div class="cc-skills">
        <button
          :for={skill <- @offered}
          class={["cc-skill", skill in @picked && "selected"]}
          type="button"
          aria-pressed={to_string(skill in @picked)}
          phx-click="creation_skill"
          phx-value-skill={skill}
        >
          <span class="cc-skill-name">{Skill.name(skill)}</span>
          <span class="cc-skill-meta">
            {ability_abbrev(skill)} {modifier_label(@draft, skill, skill in @picked)}
          </span>
        </button>
      </div>
    </fieldset>
    """
  end

  # The modifier as it stands, so the difference a pick makes is visible before
  # it is made. `nil` until the ability scores exist.
  defp modifier_label(draft, skill, proficient?) do
    case Draft.skill_modifier(draft, skill, proficient?: proficient?) do
      nil -> ""
      modifier -> signed(modifier)
    end
  end

  defp ability_abbrev(skill) do
    skill |> Skill.ability() |> Atom.to_string() |> String.upcase()
  end

  defp skill_note(%{class_slug: nil}, _picked, _allowance),
    do: "Choose a class first — it decides which skills you may train in."

  defp skill_note(_draft, picked, allowance) do
    case allowance - length(picked) do
      0 -> "All chosen."
      1 -> "One more to choose."
      n -> "#{n} more to choose."
    end
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"

  # --- Specializations ------------------------------------------------------
  #
  # One renderer for every choice the content carries. Nothing below names a
  # fighting style, a lineage, or a Divine Order: the list comes from
  # `Srd.Character.choices/1` and each entry renders from its `kind`. A choice
  # the SRD content gains tomorrow appears here with no change to this file,
  # which is FR-009 on the presentation side.

  attr :draft, :map, required: true

  defp specializations_step(assigns) do
    assigns =
      assigns
      |> assign(
        :open,
        Draft.open_choices(assigns.draft) |> Enum.reject(&(&1.key == :class_skills))
      )
      |> assign(:grants, Draft.grants(assigns.draft))

    ~H"""
    <p :if={@open == []} class="cc-lead">
      {nothing_to_choose(@draft)}
    </p>

    <fieldset :for={choice <- @open} class="cc-group">
      <legend class="cc-label">{choice.label}</legend>
      <p :if={choice.text} class="cc-lead">{choice.text}</p>
      <p class="cc-lead">{choose_note(choice, held(@draft, choice))}</p>

      <.held_options choice={choice} grants={@grants} />

      <div class="cc-options">
        <button
          :for={option <- offerable(choice, @grants)}
          class={["cc-option", option.value in held(@draft, choice) && "selected"]}
          type="button"
          aria-pressed={to_string(option.value in held(@draft, choice))}
          phx-click="creation_pick"
          phx-value-key={Draft.storage_key(choice.key)}
          phx-value-value={option.value}
        >
          <span class="cc-option-name">{option.name}</span>
          <span :if={option.detail} class="cc-option-traits">{option.detail}</span>
        </button>
      </div>
    </fieldset>
    """
  end

  attr :choice, :map, required: true
  attr :grants, :map, required: true

  # A feat or skill the character already has is shown, not offered. Spending a
  # pick on it would silently buy nothing, and saying so is the spec's
  # duplicate-feat edge case.
  defp held_options(assigns) do
    assigns = assign(assigns, :already, already_granted(assigns.choice, assigns.grants))

    ~H"""
    <div :if={@already != []} class="cc-options">
      <div :for={option <- @already} class="cc-option held">
        <span class="cc-option-name">{option.name}</span>
        <span class="cc-option-traits">already granted by your background</span>
      </div>
    </div>
    """
  end

  defp held(draft, choice), do: Map.get(draft.choices, choice.key, []) |> Enum.map(&to_string/1)

  defp choose_note(choice, held) do
    case choice.choice.choose - length(held) do
      0 -> "Chosen."
      1 -> "Choose one."
      n -> "Choose #{n}."
    end
  end

  defp nothing_to_choose(%{species_slug: nil}), do: "Choose a species and class first."

  defp nothing_to_choose(_draft),
    do: "Your species and class ask nothing more of you at this level."

  # The options that are still worth offering, and the ones already held.
  defp offerable(choice, grants) do
    granted = granted_values(choice, grants)

    choice.choice.from
    |> Enum.map(&option_view(choice.choice.kind, &1))
    |> Enum.reject(&(&1.value in granted))
  end

  defp already_granted(choice, grants) do
    granted = granted_values(choice, grants)

    choice.choice.from
    |> Enum.map(&option_view(choice.choice.kind, &1))
    |> Enum.filter(&(&1.value in granted))
  end

  defp granted_values(%{choice: %{kind: :feat}}, grants), do: Enum.map(grants.feats, &to_string/1)

  defp granted_values(%{choice: %{kind: :skill}}, grants),
    do: Enum.map(grants.skills, &to_string/1)

  defp granted_values(_choice, _grants), do: []

  # How one option of a given kind is shown. The only place in the dialog that
  # knows the shape of a lineage differs from the shape of a weapon.
  defp option_view(:lineage, lineage) do
    %{
      value: lineage.slug,
      name: lineage.name,
      detail: lineage.features |> Enum.map(& &1.name) |> Enum.join(" · ") |> blank_to_nil()
    }
  end

  defp option_view(:size, size) do
    %{value: to_string(size), name: String.capitalize(to_string(size)), detail: nil}
  end

  defp option_view(:feat, slug) do
    case Feats.get(slug) do
      nil -> %{value: slug, name: slug, detail: nil}
      feat -> %{value: feat.slug, name: feat.name, detail: feature_text(feat.features)}
    end
  end

  defp option_view(:weapon, slug) do
    case Weapons.get(slug) do
      nil -> %{value: slug, name: slug, detail: nil}
      weapon -> %{value: weapon.slug, name: weapon.name, detail: mastery_label(weapon)}
    end
  end

  defp option_view(:tool, slug) do
    case Items.get(slug) do
      nil -> %{value: slug, name: slug, detail: nil}
      item -> %{value: item.slug, name: item.name, detail: nil}
    end
  end

  defp option_view(:skill, skill) do
    %{value: to_string(skill), name: Skill.name(skill), detail: ability_abbrev(skill)}
  end

  # Feature options are plain strings the content already made readable, and a
  # kind this component has not met renders by its own name rather than
  # crashing — a new kind is a styling gap, not an outage.
  defp option_view(_kind, option) when is_binary(option),
    do: %{value: option, name: option, detail: nil}

  defp option_view(_kind, option),
    do: %{value: to_string(option), name: to_string(option), detail: nil}

  # Every weapon in the current content carries a mastery and every feat a
  # feature, but neither is guaranteed by the struct, so both read defensively
  # rather than matching a shape the data happens to have today.
  defp mastery_label(weapon) do
    case Map.get(weapon, :mastery) do
      nil -> nil
      mastery -> "Mastery: #{String.capitalize(to_string(mastery))}"
    end
  end

  defp feature_text(features) do
    case Enum.at(features, 0) do
      %{text: text} -> text
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # --- Review ---------------------------------------------------------------
  #
  # The character as it will exist, rendered through the character sheet's own
  # panels. Both this and the sheet go through `Stats.sheet/3`, so "the
  # reviewed character and the created character are identical" (FR-029) holds
  # by construction rather than by two renderings agreeing.

  attr :draft, :map, required: true

  defp review_step(assigns) do
    assigns = assign(assigns, :incomplete, Draft.first_incomplete_step(assigns.draft))

    ~H"""
    <div :if={@incomplete} class="cc-lead">
      {incomplete_note(@incomplete)}
    </div>

    <.review_sheet :if={is_nil(@incomplete)} draft={@draft} />
    """
  end

  attr :draft, :map, required: true

  defp review_sheet(assigns) do
    completed = CharacterGen.complete(assigns.draft)

    assigns =
      assigns
      |> assign(:stats, Draft.sheet(completed))
      |> assign(:grants, Draft.grants(completed))
      |> assign(:picks, review_picks(completed))

    ~H"""
    <div class="sheet-head">
      <div class="sigil sheet-sigil">{String.upcase(String.first(@stats.name))}</div>
      <div>
        <div class="sheet-name">{@stats.name}</div>
        <div class="sheet-descriptor">
          Level {@stats.level} {@stats.species.name} {@stats.class.name}
        </div>
      </div>
    </div>

    <.main_panel stats={@stats} />
    <.abilities_panel stats={@stats} />

    <div :if={@picks != []} class="cc-review-block">
      <span class="cc-label">Your Choices</span>
      <div class="cc-review-rows">
        <div :for={{label, value} <- @picks} class="cc-review-row">
          <span class="cc-review-label">{label}</span>
          <span class="cc-review-value">{value}</span>
        </div>
      </div>
    </div>

    <div :if={@grants.features != []} class="cc-review-block">
      <span class="cc-label">Features</span>
      <div class="cc-review-rows">
        <div :for={feature <- @grants.features} class="cc-review-row">
          <span class="cc-review-label">{feature.name}</span>
          <span class="cc-review-value">{feature.text}</span>
        </div>
      </div>
    </div>
    """
  end

  # Every decision the player made, labelled by the choice that asked for it.
  # Reads the same open-choice list the specializations step renders, so a new
  # kind of choice shows up here too with no change.
  defp review_picks(draft) do
    for open <- Draft.open_choices(draft),
        open.key != :class_skills,
        picks = Map.get(draft.choices, open.key, []),
        picks != [] do
      {open.label, picks |> Enum.map(&pick_name(open.choice, &1)) |> Enum.join(", ")}
    end
  end

  # The draft stores what was picked, not the option it came from, so the
  # display name is looked back up against the choice's own list.
  defp pick_name(choice, pick) do
    value = to_string(pick)

    choice.from
    |> Enum.map(&option_view(choice.kind, &1))
    |> Enum.find(&(&1.value == value))
    |> case do
      nil -> value
      option -> option.name
    end
  end

  defp incomplete_note(step),
    do: "Not quite — #{String.downcase(missing_note(step))} Then come back."

  attr :title, :string, required: true
  attr :field, :string, required: true
  attr :selected, :string, default: nil
  attr :options, :list, required: true

  defp option_group(assigns) do
    ~H"""
    <fieldset class="cc-group">
      <legend class="cc-label">{@title}</legend>
      <div class="cc-options">
        <button
          :for={option <- @options}
          class={["cc-option", @selected == option.slug && "selected"]}
          type="button"
          aria-pressed={to_string(@selected == option.slug)}
          phx-click="creation_select"
          phx-value-field={@field}
          phx-value-value={option.slug}
        >
          <span class="cc-option-name">{option.name}</span>
          <span class="cc-option-meta">{option.meta}</span>
          <span :if={option.traits != []} class="cc-option-traits">
            {Enum.join(option.traits, " · ")}
          </span>
        </button>
      </div>
    </fieldset>
    """
  end

  attr :draft, :map, required: true
  attr :steps, :list, required: true

  defp footer(assigns) do
    assigns = assign(assigns, :blocked_by, blocked_by(assigns.draft, assigns.steps))

    ~H"""
    <div class="cc-footer">
      <p class="cc-footer-hint">
        {if @blocked_by, do: missing_note(@blocked_by), else: "Ready when you are."}
      </p>
      <button
        class="cc-confirm"
        type="button"
        disabled={@blocked_by != nil}
        phx-click="creation_confirm"
      >
        Enter the world
      </button>
    </div>
    """
  end

  # The first shipped step that is not finished. Steps that have not shipped are
  # completed for the player by generation, so they never block.
  #
  # The validator is not consulted here. It runs on the *completed* draft and
  # can only fail on something the player entered, which the step checks
  # already cover; asking it would mean completing the draft on every render to
  # answer a question the steps have answered.
  defp blocked_by(draft, steps), do: Enum.find(steps, &(not Draft.complete?(draft, &1)))

  defp missing_note(:identity), do: "Give your character a name, a species, a class, and a past."
  defp missing_note(:abilities), do: "Assign your ability scores."
  defp missing_note(:skills), do: "Choose your skills."
  defp missing_note(:specializations), do: "A few choices remain."
  defp missing_note(:review), do: "Review your character."

  # --- content helpers ------------------------------------------------------
  #
  # These read from the content library and format. None of them holds a list of
  # anything, which is what keeps a new species or class from needing a change
  # here.

  defp hit_die(%Srd.Dice.Expr{count: count, sides: sides}), do: "#{count}d#{sides}"

  defp sizes(sizes), do: sizes |> Enum.map(&String.capitalize(to_string(&1))) |> Enum.join(" or ")

  defp abilities(list), do: list |> Enum.map(&Ability.name/1) |> Enum.join(", ")

  defp primary({:all, list}), do: abilities(list)
  defp primary({:any, [first | _]}), do: Ability.name(first)

  defp level_one_features(class) do
    class.features
    |> Enum.filter(&((&1.level || 0) <= 1))
    |> Enum.map(& &1.name)
  end

  defp feat_name(slug) do
    case Feats.get(slug) do
      nil -> slug
      feat -> feat.name
    end
  end

  # FR-007 — a choice the SRD defers is named, not offered.
  defp deferred_note(class_slug) do
    class = Classes.get(class_slug)
    "You will choose your #{class.name} subclass at level #{class.subclass_level}."
  end

  defp name_hint(:unchecked), do: "Up to 32 characters. This is what other players will see."
  defp name_hint(:checking), do: "Checking…"
  defp name_hint(:available), do: "That name is free."
  defp name_hint(:taken), do: "Someone already goes by that name."
  defp name_hint(:invalid), do: "That name is too long."

  defp name_hint_class(:taken), do: "bad"
  defp name_hint_class(:invalid), do: "bad"
  defp name_hint_class(:available), do: "good"
  defp name_hint_class(_), do: nil
end
