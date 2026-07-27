# SRD 5.2 feats. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD feats section:
# https://5e24srd.com/feats/index.html
#
# The 17 feats of the SRD, in four categories. Prerequisites are structured so
# `Srd.Content.Feats.eligible/1` can answer them; feature text is a concise
# restatement of the mechanics, not verbatim SRD prose.
#
# Magic Initiate names a spell list and grants spells. Spells are not part of
# this package, so the feat carries the choice of list without resolving what is
# on it.
[
  # --- Origin ---
  %{
    slug: "alert",
    name: "Alert",
    category: :origin,
    features: [
      %{
        name: "Initiative Proficiency",
        text: "Add your proficiency bonus to initiative rolls."
      },
      %{
        name: "Initiative Swap",
        text:
          "Immediately after rolling initiative, swap your initiative with a willing ally's, " <>
            "unless either of you is incapacitated."
      }
    ]
  },
  %{
    slug: "magic-initiate",
    name: "Magic Initiate",
    category: :origin,
    repeatable?: true,
    features: [
      %{
        name: "Two Cantrips",
        text:
          "Learn two cantrips from the chosen spell list, using Intelligence, Wisdom, or " <>
            "Charisma as the spellcasting ability for them.",
        choice: %{kind: :feature, choose: 1, from: ["Cleric", "Druid", "Wizard"]}
      },
      %{
        name: "Level 1 Spell",
        text:
          "Always have one level 1 spell from the same list prepared, castable once per long " <>
            "rest without a slot, or with any slot you have."
      },
      %{
        name: "Spell Change",
        text: "On gaining a level, replace one of the feat's spells with another of the same level."
      }
    ]
  },
  %{
    slug: "savage-attacker",
    name: "Savage Attacker",
    category: :origin,
    features: [
      %{
        name: "Savage Attacker",
        text:
          "Once per turn when you hit with a weapon, roll the weapon's damage dice twice and " <>
            "use either roll."
      }
    ]
  },
  %{
    slug: "skilled",
    name: "Skilled",
    category: :origin,
    repeatable?: true,
    features: [
      %{
        name: "Skilled",
        text: "Gain proficiency in any combination of three skills or tools."
      }
    ]
  },

  # --- General ---
  %{
    slug: "ability-score-improvement",
    name: "Ability Score Improvement",
    category: :general,
    prerequisites: [{:level, 4}],
    repeatable?: true,
    features: [
      %{
        name: "Ability Score Improvement",
        text: "Increase one ability score by 2, or two ability scores by 1, to a maximum of 20."
      }
    ]
  },
  %{
    slug: "grappler",
    name: "Grappler",
    category: :general,
    prerequisites: [{:level, 4}, {:ability, [:str, :dex], 13}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase your Strength or Dexterity by 1, to a maximum of 20."
      },
      %{
        name: "Punch and Grab",
        text:
          "Once per turn, when you hit with an Unarmed Strike as part of the Attack action, " <>
            "use both the Damage and the Grapple option."
      },
      %{
        name: "Attack Advantage",
        text: "You have advantage on attack rolls against a creature you have grappled."
      },
      %{
        name: "Fast Wrestler",
        text:
          "Moving a creature you have grappled costs no extra movement if it is your size or smaller."
      }
    ]
  },

  # --- Fighting Style ---
  %{
    slug: "archery",
    name: "Archery",
    category: :fighting_style,
    prerequisites: [{:feature, :fighting_style}],
    features: [
      %{name: "Archery", text: "+2 to attack rolls with ranged weapons."}
    ]
  },
  %{
    slug: "defense",
    name: "Defense",
    category: :fighting_style,
    prerequisites: [{:feature, :fighting_style}],
    features: [
      %{name: "Defense", text: "+1 to Armor Class while wearing light, medium, or heavy armor."}
    ]
  },
  %{
    slug: "great-weapon-fighting",
    name: "Great Weapon Fighting",
    category: :fighting_style,
    prerequisites: [{:feature, :fighting_style}],
    features: [
      %{
        name: "Great Weapon Fighting",
        text:
          "Treat a 1 or 2 on a damage die as a 3 when attacking two-handed with a melee weapon " <>
            "that has the Two-Handed or Versatile property."
      }
    ]
  },
  %{
    slug: "two-weapon-fighting",
    name: "Two-Weapon Fighting",
    category: :fighting_style,
    prerequisites: [{:feature, :fighting_style}],
    features: [
      %{
        name: "Two-Weapon Fighting",
        text:
          "Add your ability modifier to the damage of the extra attack made with a Light weapon."
      }
    ]
  },

  # --- Epic Boon ---
  %{
    slug: "boon-of-combat-prowess",
    name: "Boon of Combat Prowess",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase one ability score by 1, to a maximum of 30."
      },
      %{
        name: "Peerless Aim",
        text: "Turn one miss into a hit; usable again at the start of your next turn."
      }
    ]
  },
  %{
    slug: "boon-of-dimensional-travel",
    name: "Boon of Dimensional Travel",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase one ability score by 1, to a maximum of 30."
      },
      %{
        name: "Blink Steps",
        text:
          "After taking the Attack or Magic action, teleport up to 30 feet to a space you can see."
      }
    ]
  },
  %{
    slug: "boon-of-fate",
    name: "Boon of Fate",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase one ability score by 1, to a maximum of 30."
      },
      %{
        name: "Improve Fate",
        text:
          "When you or a creature within 60 feet succeeds or fails a d20 test, roll 2d4 and " <>
            "apply the total as a bonus or penalty. Recharges on initiative or a rest."
      }
    ]
  },
  %{
    slug: "boon-of-irresistible-offense",
    name: "Boon of Irresistible Offense",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase your Strength or Dexterity by 1, to a maximum of 30."
      },
      %{
        name: "Overcome Defenses",
        text: "Your bludgeoning, piercing, and slashing damage ignores resistance."
      },
      %{
        name: "Overwhelming Strike",
        text:
          "On a natural 20 on an attack roll, deal extra damage of the attack's type equal to " <>
            "the ability score this feat increased."
      }
    ]
  },
  %{
    slug: "boon-of-spell-recall",
    name: "Boon of Spell Recall",
    category: :epic_boon,
    prerequisites: [{:level, 19}, {:feature, :spellcasting}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase your Intelligence, Wisdom, or Charisma by 1, to a maximum of 30."
      },
      %{
        name: "Free Casting",
        text:
          "When you cast a spell with a level 1-4 slot, roll 1d4; on a result equal to the " <>
            "slot's level, the slot isn't expended."
      }
    ]
  },
  %{
    slug: "boon-of-the-night-spirit",
    name: "Boon of the Night Spirit",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase one ability score by 1, to a maximum of 30."
      },
      %{
        name: "Merge with Shadows",
        text:
          "In dim light or darkness, become invisible as a bonus action until you act, react, " <>
            "or take a bonus action."
      },
      %{
        name: "Shadowy Form",
        text: "In dim light or darkness, you have resistance to all damage except psychic and radiant."
      }
    ]
  },
  %{
    slug: "boon-of-truesight",
    name: "Boon of Truesight",
    category: :epic_boon,
    prerequisites: [{:level, 19}],
    features: [
      %{
        name: "Ability Score Increase",
        text: "Increase one ability score by 1, to a maximum of 30."
      },
      %{name: "Truesight", text: "You have truesight out to 60 feet."}
    ]
  }
]
