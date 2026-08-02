defmodule AgenticRealmsWeb.GameComponents do
  @moduledoc """
  Facade for the game HEEx components, split into focused submodules
  under `lib/agenticrealms_web/components/game/`:

    * `Primitives`       — hp_bar, hud_card, modal, stats_panel,
                           direction_arrow
    * `LogEntry`         — log_entry/1 (one clause per entry kind)
    * `MiniMap`          — mini_map/1 + colocated MapInteract hook
    * `PlayerModals`     — stats_modal, inventory_modal, quest_modal,
                           presence_modal
    * `CharacterCreation` — character_creation_modal/1 (feature 021)
    * `PlayerView`       — player_view/1
    * `WizardAuthoring`  — wizard_authoring_view/1 + draft forms +
                           commit-error formatter

  Call sites just `use AgenticRealmsWeb.GameComponents` to pull every
  public component into scope as a `<.name>` HEEx callable.
  """

  defmacro __using__(_opts) do
    quote do
      import AgenticRealmsWeb.GameComponents.Primitives
      import AgenticRealmsWeb.GameComponents.LogEntry
      import AgenticRealmsWeb.GameComponents.MiniMap
      import AgenticRealmsWeb.GameComponents.PlayerModals
      import AgenticRealmsWeb.GameComponents.CharacterCreation
      import AgenticRealmsWeb.GameComponents.PlayerView
      import AgenticRealmsWeb.GameComponents.WizardAuthoring
    end
  end
end
