# SRD 5.2 species. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD character origins section:
# https://5e24srd.com/character-origins/character-species.html
#
# The nine species of the SRD. The 2024 rules have no races and no subraces:
# where a species offers a further choice it is a trait of that species, named
# in `lineage_trait`, with its options in `lineages`. Dwarves, halflings,
# humans, and orcs offer nothing at that tier, so their `lineages` is empty.
#
# Several lineages grant spells at levels 3 and 5. Spells are not part of this
# package, so those features name the spell without resolving it.
[
  %{
    slug: "dragonborn",
    name: "Dragonborn",
    sizes: [:medium],
    speed: 30,
    lineage_trait: "Draconic Ancestry",
    features: [
      %{
        level: 1,
        name: "Breath Weapon",
        text:
          "Replace one attack with a 15-foot cone or 30-foot line; each creature makes a " <>
            "Dexterity save (DC 8 + Constitution modifier + proficiency bonus) or takes 1d10 " <>
            "damage of your ancestry's type, half on a success. The damage rises by 1d10 at " <>
            "levels 5, 11, and 17. Uses equal to your proficiency bonus, regained on a long rest."
      },
      %{
        level: 1,
        name: "Damage Resistance",
        text: "You have resistance to the damage type your draconic ancestry determines."
      },
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 60 feet."},
      %{
        level: 5,
        name: "Draconic Flight",
        text:
          "As a bonus action, sprout spectral wings for 10 minutes, gaining a fly speed equal " <>
            "to your speed. Once per long rest."
      }
    ],
    lineages: [
      %{slug: "black", name: "Black", damage_type: :acid},
      %{slug: "blue", name: "Blue", damage_type: :lightning},
      %{slug: "brass", name: "Brass", damage_type: :fire},
      %{slug: "bronze", name: "Bronze", damage_type: :lightning},
      %{slug: "copper", name: "Copper", damage_type: :acid},
      %{slug: "gold", name: "Gold", damage_type: :fire},
      %{slug: "green", name: "Green", damage_type: :poison},
      %{slug: "red", name: "Red", damage_type: :fire},
      %{slug: "silver", name: "Silver", damage_type: :cold},
      %{slug: "white", name: "White", damage_type: :cold}
    ]
  },
  %{
    slug: "dwarf",
    name: "Dwarf",
    sizes: [:medium],
    speed: 30,
    features: [
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 120 feet."},
      %{
        level: 1,
        name: "Dwarven Resilience",
        text:
          "You have resistance to poison damage and advantage on saves to avoid or end the " <>
            "poisoned condition."
      },
      %{
        level: 1,
        name: "Dwarven Toughness",
        text: "Your hit point maximum increases by 1, and by 1 again at every level."
      },
      %{
        level: 1,
        name: "Stonecunning",
        text:
          "As a bonus action while on or touching stone, gain tremorsense out to 60 feet for " <>
            "10 minutes. Uses equal to your proficiency bonus, regained on a long rest."
      }
    ]
  },
  %{
    slug: "elf",
    name: "Elf",
    sizes: [:medium],
    speed: 30,
    lineage_trait: "Elven Lineage",
    features: [
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 60 feet."},
      %{
        level: 1,
        name: "Fey Ancestry",
        text: "You have advantage on saves to avoid or end the charmed condition."
      },
      %{
        level: 1,
        name: "Keen Senses",
        text: "You have proficiency in one of Insight, Perception, or Survival.",
        choice: %{kind: :skill, choose: 1, from: [:insight, :perception, :survival]}
      },
      %{
        level: 1,
        name: "Trance",
        text:
          "You don't need to sleep and magic can't put you to sleep. You finish a long rest in " <>
            "4 hours of trancelike meditation."
      }
    ],
    lineages: [
      %{
        slug: "drow",
        name: "Drow",
        features: [
          %{
            level: 1,
            name: "Drow",
            text: "Your darkvision increases to 120 feet, and you know the Dancing Lights cantrip."
          },
          %{level: 3, name: "Faerie Fire", text: "You always have Faerie Fire prepared."},
          %{level: 5, name: "Darkness", text: "You always have Darkness prepared."}
        ]
      },
      %{
        slug: "high-elf",
        name: "High Elf",
        features: [
          %{
            level: 1,
            name: "High Elf",
            text:
              "You know the Prestidigitation cantrip, and can swap it for another Wizard " <>
                "cantrip on each long rest."
          },
          %{level: 3, name: "Detect Magic", text: "You always have Detect Magic prepared."},
          %{level: 5, name: "Misty Step", text: "You always have Misty Step prepared."}
        ]
      },
      %{
        slug: "wood-elf",
        name: "Wood Elf",
        features: [
          %{
            level: 1,
            name: "Wood Elf",
            text: "Your speed increases to 35 feet, and you know the Druidcraft cantrip."
          },
          %{level: 3, name: "Longstrider", text: "You always have Longstrider prepared."},
          %{
            level: 5,
            name: "Pass without Trace",
            text: "You always have Pass without Trace prepared."
          }
        ]
      }
    ]
  },
  %{
    slug: "gnome",
    name: "Gnome",
    sizes: [:small],
    speed: 30,
    lineage_trait: "Gnomish Lineage",
    features: [
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 60 feet."},
      %{
        level: 1,
        name: "Gnomish Cunning",
        text: "You have advantage on Intelligence, Wisdom, and Charisma saving throws."
      }
    ],
    lineages: [
      %{
        slug: "forest-gnome",
        name: "Forest Gnome",
        features: [
          %{
            level: 1,
            name: "Forest Gnome",
            text:
              "You know the Minor Illusion cantrip and always have Speak with Animals prepared, " <>
                "castable without a slot a number of times equal to your proficiency bonus."
          }
        ]
      },
      %{
        slug: "rock-gnome",
        name: "Rock Gnome",
        features: [
          %{
            level: 1,
            name: "Rock Gnome",
            text:
              "You know the Mending and Prestidigitation cantrips, and can spend 10 minutes " <>
                "casting Prestidigitation to build a Tiny clockwork device (AC 5, 1 HP) with " <>
                "one chosen effect. Up to three devices at a time, each lasting 8 hours."
          }
        ]
      }
    ]
  },
  %{
    slug: "goliath",
    name: "Goliath",
    sizes: [:medium],
    speed: 35,
    lineage_trait: "Giant Ancestry",
    features: [
      %{
        level: 1,
        name: "Powerful Build",
        text:
          "You have advantage on checks to end the grappled condition and count as one size " <>
            "larger for carrying capacity."
      },
      %{
        level: 5,
        name: "Large Form",
        text:
          "As a bonus action, become Large for 10 minutes, with advantage on Strength checks " <>
            "and +10 feet of speed. Once per long rest."
      }
    ],
    lineages: [
      %{
        slug: "clouds-jaunt",
        name: "Cloud's Jaunt",
        features: [
          %{
            level: 1,
            name: "Cloud's Jaunt",
            text: "As a bonus action, teleport up to 30 feet to a space you can see."
          }
        ]
      },
      %{
        slug: "fires-burn",
        name: "Fire's Burn",
        features: [
          %{
            level: 1,
            name: "Fire's Burn",
            text: "When you hit and damage a target, also deal 1d10 fire damage to it."
          }
        ]
      },
      %{
        slug: "frosts-chill",
        name: "Frost's Chill",
        features: [
          %{
            level: 1,
            name: "Frost's Chill",
            text:
              "When you hit and damage a target, also deal 1d6 cold damage and reduce its " <>
                "speed by 10 feet until the start of your next turn."
          }
        ]
      },
      %{
        slug: "hills-tumble",
        name: "Hill's Tumble",
        features: [
          %{
            level: 1,
            name: "Hill's Tumble",
            text: "When you hit and damage a Large or smaller creature, give it the prone condition."
          }
        ]
      },
      %{
        slug: "stones-endurance",
        name: "Stone's Endurance",
        features: [
          %{
            level: 1,
            name: "Stone's Endurance",
            text:
              "As a reaction to taking damage, roll 1d12 and reduce the damage by the roll plus " <>
                "your Constitution modifier."
          }
        ]
      },
      %{
        slug: "storms-thunder",
        name: "Storm's Thunder",
        features: [
          %{
            level: 1,
            name: "Storm's Thunder",
            text:
              "As a reaction to taking damage from a creature within 60 feet, deal 1d8 thunder " <>
                "damage to it."
          }
        ]
      }
    ]
  },
  %{
    slug: "halfling",
    name: "Halfling",
    sizes: [:small],
    speed: 30,
    features: [
      %{
        level: 1,
        name: "Brave",
        text: "You have advantage on saves to avoid or end the frightened condition."
      },
      %{
        level: 1,
        name: "Halfling Nimbleness",
        text: "You can move through the space of any creature a size larger than you."
      },
      %{level: 1, name: "Luck", text: "When you roll a 1 on a d20 test, reroll and use the new roll."},
      %{
        level: 1,
        name: "Naturally Stealthy",
        text: "You can hide even when obscured only by a creature at least one size larger."
      }
    ]
  },
  %{
    slug: "human",
    name: "Human",
    sizes: [:small, :medium],
    speed: 30,
    features: [
      %{
        level: 1,
        name: "Resourceful",
        text: "You gain heroic inspiration whenever you finish a long rest."
      },
      %{
        level: 1,
        name: "Skillful",
        text: "You gain proficiency in one skill of your choice.",
        choice: %{
          kind: :skill,
          choose: 1,
          from: [
            :acrobatics,
            :animal_handling,
            :arcana,
            :athletics,
            :deception,
            :history,
            :insight,
            :intimidation,
            :investigation,
            :medicine,
            :nature,
            :perception,
            :performance,
            :persuasion,
            :religion,
            :sleight_of_hand,
            :stealth,
            :survival
          ]
        }
      },
      %{
        level: 1,
        name: "Versatile",
        text: "You gain an origin feat of your choice; Skilled is recommended.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :origin}}
      }
    ]
  },
  %{
    slug: "orc",
    name: "Orc",
    sizes: [:medium],
    speed: 30,
    features: [
      %{
        level: 1,
        name: "Adrenaline Rush",
        text:
          "Take the Dash action as a bonus action and gain temporary hit points equal to your " <>
            "proficiency bonus. Uses equal to your proficiency bonus, regained on a short or " <>
            "long rest."
      },
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 120 feet."},
      %{
        level: 1,
        name: "Relentless Endurance",
        text:
          "When reduced to 0 hit points without being killed outright, drop to 1 instead. Once " <>
            "per long rest."
      }
    ]
  },
  %{
    slug: "tiefling",
    name: "Tiefling",
    sizes: [:small, :medium],
    speed: 30,
    lineage_trait: "Fiendish Legacy",
    features: [
      %{level: 1, name: "Darkvision", text: "You have darkvision out to 60 feet."},
      %{
        level: 1,
        name: "Otherworldly Presence",
        text:
          "You know the Thaumaturgy cantrip, cast with the same ability as your fiendish legacy."
      }
    ],
    lineages: [
      %{
        slug: "abyssal",
        name: "Abyssal",
        features: [
          %{
            level: 1,
            name: "Abyssal",
            text: "You have resistance to poison damage and know the Poison Spray cantrip."
          },
          %{level: 3, name: "Ray of Sickness", text: "You always have Ray of Sickness prepared."},
          %{level: 5, name: "Hold Person", text: "You always have Hold Person prepared."}
        ]
      },
      %{
        slug: "chthonic",
        name: "Chthonic",
        features: [
          %{
            level: 1,
            name: "Chthonic",
            text: "You have resistance to necrotic damage and know the Chill Touch cantrip."
          },
          %{level: 3, name: "False Life", text: "You always have False Life prepared."},
          %{
            level: 5,
            name: "Ray of Enfeeblement",
            text: "You always have Ray of Enfeeblement prepared."
          }
        ]
      },
      %{
        slug: "infernal",
        name: "Infernal",
        features: [
          %{
            level: 1,
            name: "Infernal",
            text: "You have resistance to fire damage and know the Fire Bolt cantrip."
          },
          %{level: 3, name: "Hellish Rebuke", text: "You always have Hellish Rebuke prepared."},
          %{level: 5, name: "Darkness", text: "You always have Darkness prepared."}
        ]
      }
    ]
  }
]
