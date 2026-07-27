# SRD 5.2 subclasses. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD classes section:
# https://5e24srd.com/classes/index.html
#
# The SRD carries exactly one subclass per class, chosen at the class's
# subclass level. `class` is checked against `Srd.Content.Classes` while
# compiling. Feature text is a concise restatement of the mechanics, not
# verbatim SRD prose.
#
# Several subclasses grant always-prepared spells. Spells are not part of this
# package, so those features record that the list exists without resolving it.
[
  %{
    slug: "path-of-the-berserker",
    name: "Path of the Berserker",
    class: "barbarian",
    features: [
      %{
        level: 3,
        name: "Frenzy",
        text:
          "While raging, using Reckless Attack deals extra damage to the first target you hit " <>
            "with a Strength attack: d6s equal to your Rage Damage bonus, of the weapon's type."
      },
      %{
        level: 6,
        name: "Mindless Rage",
        text:
          "While raging, you are immune to charmed and frightened, and entering a rage ends " <>
            "those conditions on you."
      },
      %{
        level: 10,
        name: "Retaliation",
        text:
          "As a reaction to taking damage from a creature within 5 feet, make one melee attack " <>
            "against it."
      },
      %{
        level: 14,
        name: "Intimidating Presence",
        text:
          "As a bonus action, creatures of your choice within 30 feet make a Wisdom save (DC 8 " <>
            "+ Strength modifier + proficiency bonus) or are frightened for 1 minute. Once per " <>
            "long rest, or by expending a use of Rage."
      }
    ]
  },
  %{
    slug: "college-of-lore",
    name: "College of Lore",
    class: "bard",
    features: [
      %{
        level: 3,
        name: "Bonus Proficiencies",
        text: "Gain proficiency with three skills of your choice.",
        choice: %{
          kind: :skill,
          choose: 3,
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
        level: 3,
        name: "Cutting Words",
        text:
          "As a reaction when a creature within 60 feet makes a damage roll or succeeds on a " <>
            "check or attack roll, expend a use of Bardic Inspiration and subtract the die roll " <>
            "from its roll."
      },
      %{
        level: 6,
        name: "Magical Discoveries",
        text:
          "Learn two spells from the cleric, druid, or wizard lists, always prepared, swapping " <>
            "one whenever you gain a bard level."
      },
      %{
        level: 14,
        name: "Peerless Skill",
        text:
          "On a failed ability check or attack roll, expend a use of Bardic Inspiration to add " <>
            "the die to the d20. The use isn't spent if it still fails."
      }
    ]
  },
  %{
    slug: "life-domain",
    name: "Life Domain",
    class: "cleric",
    features: [
      %{
        level: 3,
        name: "Disciple of Life",
        text:
          "When a spell you cast with a slot restores hit points, the target regains an extra " <>
            "2 plus the slot's level."
      },
      %{
        level: 3,
        name: "Life Domain Spells",
        text:
          "Always have the domain's spells prepared as you reach the levels its table lists. " <>
            "The spells themselves are not part of this package."
      },
      %{
        level: 3,
        name: "Preserve Life",
        text:
          "As a magic action, expend a use of Channel Divinity to restore hit points equal to " <>
            "five times your cleric level, divided among bloodied creatures within 30 feet, to " <>
            "no more than half a creature's maximum."
      },
      %{
        level: 6,
        name: "Blessed Healer",
        text:
          "When a spell you cast with a slot restores hit points to others, you regain 2 plus " <>
            "the slot's level."
      },
      %{
        level: 17,
        name: "Supreme Healing",
        text: "Healing dice from your spells and Channel Divinity roll their maximum instead."
      }
    ]
  },
  %{
    slug: "circle-of-the-land",
    name: "Circle of the Land",
    class: "druid",
    features: [
      %{
        level: 3,
        name: "Circle of the Land Spells",
        text:
          "On each long rest, choose arid, polar, temperate, or tropical land; you have that " <>
            "land's spells prepared for your level. The spells themselves are not part of this " <>
            "package.",
        choice: %{
          kind: :feature,
          choose: 1,
          from: ["Arid", "Polar", "Temperate", "Tropical"]
        }
      },
      %{
        level: 3,
        name: "Land's Aid",
        text:
          "As a magic action, expend a use of Wild Shape: creatures of your choice in a 10-foot " <>
            "sphere within 60 feet make a Constitution save for 2d6 necrotic damage, half on a " <>
            "success, and one creature there regains 2d6 hit points. Both rise at levels 10 and 14."
      },
      %{
        level: 6,
        name: "Natural Recovery",
        text:
          "Cast one prepared circle spell without a slot per long rest, and recover slots " <>
            "totaling half your druid level on a short rest."
      },
      %{
        level: 10,
        name: "Nature's Ward",
        text:
          "You are immune to the poisoned condition and resistant to the damage type tied to " <>
            "your current land choice."
      },
      %{
        level: 14,
        name: "Nature's Sanctuary",
        text:
          "As a magic action, expend a use of Wild Shape to raise a 15-foot cube of spectral " <>
            "growth for 1 minute, granting you and allies half cover and your Nature's Ward " <>
            "resistance."
      }
    ]
  },
  %{
    slug: "champion",
    name: "Champion",
    class: "fighter",
    features: [
      %{
        level: 3,
        name: "Improved Critical",
        text: "Your attack rolls with weapons and unarmed strikes score a critical hit on a 19 or 20."
      },
      %{
        level: 3,
        name: "Remarkable Athlete",
        text:
          "You have advantage on initiative rolls and Athletics checks, and can move up to half " <>
            "your speed after a critical hit without provoking opportunity attacks."
      },
      %{
        level: 7,
        name: "Additional Fighting Style",
        text: "Gain another Fighting Style feat.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :fighting_style}}
      },
      %{
        level: 10,
        name: "Heroic Warrior",
        text: "During combat, give yourself heroic inspiration whenever you start a turn without it."
      },
      %{
        level: 15,
        name: "Superior Critical",
        text: "Your critical hit range widens to 18-20."
      },
      %{
        level: 18,
        name: "Survivor",
        text:
          "You have advantage on death saving throws and treat 18-20 on them as a 20, and " <>
            "regain hit points at the start of each turn while bloodied."
      }
    ]
  },
  %{
    slug: "warrior-of-the-open-hand",
    name: "Warrior of the Open Hand",
    class: "monk",
    features: [
      %{
        level: 3,
        name: "Open Hand Technique",
        text:
          "On a hit from Flurry of Blows, impose Addle, Push, or Topple on the target.",
        choice: %{kind: :feature, choose: 1, from: ["Addle", "Push", "Topple"]}
      },
      %{
        level: 6,
        name: "Wholeness of Body",
        text:
          "As a bonus action, heal a Martial Arts die plus your Wisdom modifier, a number of " <>
            "times equal to your Wisdom modifier per long rest."
      },
      %{
        level: 11,
        name: "Fleet Step",
        text: "Taking any other bonus action lets you also use Step of the Wind right after it."
      },
      %{
        level: 17,
        name: "Quivering Palm",
        text:
          "On an unarmed strike hit, spend 4 focus points to set vibrations lasting days equal " <>
            "to your monk level; ending them forces a Constitution save for 10d12 force damage, " <>
            "half on a success."
      }
    ]
  },
  %{
    slug: "oath-of-devotion",
    name: "Oath of Devotion",
    class: "paladin",
    features: [
      %{
        level: 3,
        name: "Oath of Devotion Spells",
        text:
          "Always have the oath's spells prepared as you reach the levels its table lists. The " <>
            "spells themselves are not part of this package."
      },
      %{
        level: 3,
        name: "Sacred Weapon",
        text:
          "When you take the Attack action, expend a use of Channel Divinity to add your " <>
            "Charisma modifier to attack rolls with one melee weapon for 10 minutes, dealing " <>
            "radiant damage at your option and shedding bright light."
      },
      %{
        level: 7,
        name: "Aura of Devotion",
        text: "You and allies in your Aura of Protection are immune to the charmed condition."
      },
      %{
        level: 15,
        name: "Smite of Protection",
        text:
          "When you cast Divine Smite, you and allies in your aura have half cover until the " <>
            "start of your next turn."
      },
      %{
        level: 20,
        name: "Holy Nimbus",
        text:
          "As a bonus action, imbue your aura for 10 minutes: advantage on saves forced by " <>
            "fiends and undead, and radiant damage to your enemies within it. Once per long rest."
      }
    ]
  },
  %{
    slug: "hunter",
    name: "Hunter",
    class: "ranger",
    features: [
      %{
        level: 3,
        name: "Hunter's Lore",
        text:
          "You know the immunities, resistances, and vulnerabilities of a creature marked by " <>
            "your Hunter's Mark."
      },
      %{
        level: 3,
        name: "Hunter's Prey",
        text:
          "Choose Colossus Slayer, adding 1d8 damage once per turn to a wounded target, or " <>
            "Horde Breaker, allowing a second attack against a different nearby creature. Swap " <>
            "on a rest.",
        choice: %{kind: :feature, choose: 1, from: ["Colossus Slayer", "Horde Breaker"]}
      },
      %{
        level: 7,
        name: "Defensive Tactics",
        text:
          "Choose Escape the Horde, giving opportunity attacks against you disadvantage, or " <>
            "Multiattack Defense, giving a creature's later attacks against you disadvantage. " <>
            "Swap on a rest.",
        choice: %{kind: :feature, choose: 1, from: ["Escape the Horde", "Multiattack Defense"]}
      },
      %{
        level: 11,
        name: "Superior Hunter's Prey",
        text:
          "Once per turn, deal your Hunter's Mark extra damage to a second creature within 30 " <>
            "feet of the marked one."
      },
      %{
        level: 15,
        name: "Superior Hunter's Defense",
        text:
          "As a reaction to taking damage, gain resistance to that damage type until the end of " <>
            "the turn."
      }
    ]
  },
  %{
    slug: "thief",
    name: "Thief",
    class: "rogue",
    features: [
      %{
        level: 3,
        name: "Fast Hands",
        text:
          "As a bonus action, make a Sleight of Hand check to pick a lock, disarm a trap, or " <>
            "pick a pocket, or use an object."
      },
      %{
        level: 3,
        name: "Second-Story Work",
        text:
          "You gain a climb speed equal to your speed, and your running jump distance uses your " <>
            "Dexterity modifier."
      },
      %{
        level: 9,
        name: "Supreme Sneak",
        text:
          "Gain the Stealth Attack Cunning Strike option, which keeps you hidden when you end " <>
            "the turn behind cover."
      },
      %{
        level: 13,
        name: "Use Magic Device",
        text: "Attune to up to four magic items, and use scrolls and charged items more freely."
      },
      %{
        level: 17,
        name: "Thief's Reflexes",
        text:
          "Take two turns in the first round of combat, the second at your initiative minus 10."
      }
    ]
  },
  %{
    slug: "draconic-sorcery",
    name: "Draconic Sorcery",
    class: "sorcerer",
    features: [
      %{
        level: 3,
        name: "Draconic Resilience",
        text:
          "Your hit point maximum increases by 3, and by 1 at each later sorcerer level. " <>
            "Unarmored, your base Armor Class is 10 plus your Dexterity and Charisma modifiers."
      },
      %{
        level: 3,
        name: "Draconic Spells",
        text:
          "Always have the subclass's spells prepared as you reach the levels its table lists. " <>
            "The spells themselves are not part of this package."
      },
      %{
        level: 6,
        name: "Elemental Affinity",
        text:
          "Choose acid, cold, fire, lightning, or poison: you have resistance to it, and add " <>
            "your Charisma modifier to one damage roll of your spells of that type.",
        choice: %{kind: :feature, choose: 1, from: ["Acid", "Cold", "Fire", "Lightning", "Poison"]}
      },
      %{
        level: 14,
        name: "Dragon Wings",
        text:
          "As a bonus action, gain a fly speed of 60 feet for 1 hour. Once per long rest, or by " <>
            "spending 3 sorcery points."
      },
      %{
        level: 18,
        name: "Dragon Companion",
        text:
          "Cast Summon Dragon without material components, and once per long rest without a " <>
            "spell slot."
      }
    ]
  },
  %{
    slug: "fiend-patron",
    name: "Fiend Patron",
    class: "warlock",
    features: [
      %{
        level: 3,
        name: "Dark One's Blessing",
        text:
          "When you or an ally within 10 feet reduces an enemy to 0 hit points, gain temporary " <>
            "hit points equal to your Charisma modifier plus your warlock level."
      },
      %{
        level: 3,
        name: "Fiend Spells",
        text:
          "Always have the patron's spells prepared as you reach the levels its table lists. " <>
            "The spells themselves are not part of this package."
      },
      %{
        level: 6,
        name: "Dark One's Own Luck",
        text:
          "Add 1d10 to an ability check or saving throw after seeing the roll, a number of " <>
            "times equal to your Charisma modifier per long rest."
      },
      %{
        level: 10,
        name: "Fiendish Resilience",
        text:
          "On each short or long rest, choose a damage type other than force; you have " <>
            "resistance to it until you choose another."
      },
      %{
        level: 14,
        name: "Hurl Through Hell",
        text:
          "Once per turn on a hit, the target makes a Charisma save or is hurled through the " <>
            "Lower Planes, taking 8d10 psychic damage if it isn't a fiend and returning " <>
            "incapacitated. Once per long rest, or by expending a pact slot."
      }
    ]
  },
  %{
    slug: "evoker",
    name: "Evoker",
    class: "wizard",
    features: [
      %{
        level: 3,
        name: "Evocation Savant",
        text:
          "Add two evocation spells of level 2 or lower to your spellbook for free, and one " <>
            "more each time you gain a new spell slot level."
      },
      %{
        level: 3,
        name: "Potent Cantrip",
        text:
          "When a creature succeeds on a save against your cantrip or you miss with its attack " <>
            "roll, it still takes half the cantrip's damage."
      },
      %{
        level: 6,
        name: "Sculpt Spells",
        text:
          "When you cast an evocation spell, a number of creatures equal to 1 plus the spell's " <>
            "level automatically succeed on their saves and take no damage from it."
      },
      %{
        level: 10,
        name: "Empowered Evocation",
        text: "Add your Intelligence modifier to one damage roll of any wizard evocation spell."
      },
      %{
        level: 14,
        name: "Overchannel",
        text:
          "Deal maximum damage with a damaging wizard spell of level 1-5. The first use per " <>
            "long rest is free; later uses cost 2d12 necrotic damage per slot level."
      }
    ]
  }
]
