# SRD 5.2 backgrounds. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD character origins section:
# https://5e24srd.com/character-origins/character-backgrounds.html
#
# The four backgrounds of the SRD. Each lists three ability scores (increase one
# by 2 and another by 1, or all three by 1 - see `Srd.Content.Background.spreads/0`),
# grants a specified origin feat, two skill proficiencies, one tool proficiency,
# and a choice between a package of equipment and 50 GP.
#
# `origin_feat_option` records the choice the background fixes for its feat:
# Acolyte and Sage both grant Magic Initiate, on the Cleric and Wizard lists
# respectively. Spells are not part of this package, so the list is named but
# not resolved.
[
  %{
    slug: "acolyte",
    name: "Acolyte",
    ability_scores: [:int, :wis, :cha],
    origin_feat: "magic-initiate",
    origin_feat_option: "Cleric",
    skills: [:insight, :religion],
    tool: %{kind: :tool, choose: 1, from: ["calligraphers-supplies"]},
    equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "calligraphers-supplies",
            %{item: "book", quantity: 1, variant: "Prayers"},
            "holy-symbol",
            {"parchment", 10},
            "robe"
          ],
          gp: 8
        },
        %{items: [], gp: 50}
      ]
    }
  },
  %{
    slug: "criminal",
    name: "Criminal",
    ability_scores: [:dex, :con, :int],
    origin_feat: "alert",
    skills: [:sleight_of_hand, :stealth],
    tool: %{kind: :tool, choose: 1, from: ["thieves-tools"]},
    equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            {"dagger", 2},
            "thieves-tools",
            "crowbar",
            {"pouch", 2},
            "travelers-clothes"
          ],
          gp: 16
        },
        %{items: [], gp: 50}
      ]
    }
  },
  %{
    slug: "sage",
    name: "Sage",
    ability_scores: [:con, :int, :wis],
    origin_feat: "magic-initiate",
    origin_feat_option: "Wizard",
    skills: [:arcana, :history],
    tool: %{kind: :tool, choose: 1, from: ["calligraphers-supplies"]},
    equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "quarterstaff",
            "calligraphers-supplies",
            %{item: "book", quantity: 1, variant: "History"},
            {"parchment", 8},
            "robe"
          ],
          gp: 8
        },
        %{items: [], gp: 50}
      ]
    }
  },
  %{
    slug: "soldier",
    name: "Soldier",
    ability_scores: [:str, :dex, :con],
    origin_feat: "savage-attacker",
    skills: [:athletics, :intimidation],
    tool: %{kind: :tool, choose: 1, from: {:items, :gaming_set}},
    equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "spear",
            "shortbow",
            {"arrows", 20},
            "healers-kit",
            "quiver",
            "travelers-clothes"
          ],
          # The gaming set is the same kind chosen for the tool proficiency.
          choices: [%{kind: :tool, choose: 1, from: {:items, :gaming_set}}],
          gp: 14
        },
        %{items: [], gp: 50}
      ]
    }
  }
]
