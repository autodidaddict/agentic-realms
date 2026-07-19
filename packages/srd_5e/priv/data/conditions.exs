# SRD 5.2 conditions. See the package README for the SRD CC-BY attribution.
#
# The 15 conditions of the 2024 rules. Effect text is a concise, accurate
# restatement of each condition's mechanics, not verbatim SRD prose.
[
  %{
    slug: "blinded",
    name: "Blinded",
    effects: [
      "Can't see, and automatically fails any ability check that requires sight.",
      "Attack rolls against the creature have Advantage, and its attack rolls have Disadvantage."
    ]
  },
  %{
    slug: "charmed",
    name: "Charmed",
    effects: [
      "Can't attack the charmer or target the charmer with damaging abilities or magical effects.",
      "The charmer has Advantage on any ability check to interact with the creature socially."
    ]
  },
  %{
    slug: "deafened",
    name: "Deafened",
    effects: [
      "Can't hear, and automatically fails any ability check that requires hearing."
    ]
  },
  %{
    slug: "exhaustion",
    name: "Exhaustion",
    effects: [
      "Is measured in levels and is cumulative: each time it is gained, the Exhaustion level rises by 1.",
      "The creature dies if its Exhaustion level reaches 6.",
      "Every D20 Test the creature makes is reduced by 2 times its Exhaustion level.",
      "Its Speed is reduced by a number of feet equal to 5 times its Exhaustion level.",
      "Finishing a Long Rest removes 1 Exhaustion level."
    ]
  },
  %{
    slug: "frightened",
    name: "Frightened",
    effects: [
      "Has Disadvantage on ability checks and attack rolls while the source of its fear is within line of sight.",
      "Can't willingly move closer to the source of its fear."
    ]
  },
  %{
    slug: "grappled",
    name: "Grappled",
    effects: [
      "Its Speed is 0 and can't increase.",
      "Has Disadvantage on attack rolls against any target other than the grappler.",
      "Moves with the grappler when the grappler moves it, and the condition ends if the grappler is Incapacitated."
    ]
  },
  %{
    slug: "incapacitated",
    name: "Incapacitated",
    effects: [
      "Can't take any action, Bonus Action, or Reaction.",
      "Concentration is broken.",
      "Can't speak.",
      "If it becomes Incapacitated when it rolls Initiative, it has Disadvantage on the roll."
    ]
  },
  %{
    slug: "invisible",
    name: "Invisible",
    effects: [
      "Can't be seen without the aid of magic or a special sense, and counts as heavily obscured for being found.",
      "Attack rolls against the creature have Disadvantage, and its attack rolls have Advantage.",
      "If Invisible when it rolls Initiative, it has Advantage on the roll."
    ]
  },
  %{
    slug: "paralyzed",
    name: "Paralyzed",
    effects: [
      "Is Incapacitated and can't move or speak.",
      "Automatically fails Strength and Dexterity saving throws.",
      "Attack rolls against the creature have Advantage.",
      "Any attack that hits it is a critical hit if the attacker is within 5 feet."
    ]
  },
  %{
    slug: "petrified",
    name: "Petrified",
    effects: [
      "Is transformed, with any nonmagical objects it is wearing or carrying, into a solid inanimate substance; its weight increases tenfold and it stops aging.",
      "Is Incapacitated, can't move or speak, and is unaware of its surroundings.",
      "Automatically fails Strength and Dexterity saving throws.",
      "Attack rolls against the creature have Advantage.",
      "Has Resistance to all damage and is immune to poison and disease."
    ]
  },
  %{
    slug: "poisoned",
    name: "Poisoned",
    effects: [
      "Has Disadvantage on attack rolls and ability checks."
    ]
  },
  %{
    slug: "prone",
    name: "Prone",
    effects: [
      "Can only crawl unless it stands up, which costs half its Speed and ends the condition.",
      "Has Disadvantage on attack rolls.",
      "Attack rolls against it have Advantage if the attacker is within 5 feet, and Disadvantage otherwise."
    ]
  },
  %{
    slug: "restrained",
    name: "Restrained",
    effects: [
      "Its Speed is 0 and can't increase.",
      "Attack rolls against the creature have Advantage, and its attack rolls have Disadvantage.",
      "Has Disadvantage on Dexterity saving throws."
    ]
  },
  %{
    slug: "stunned",
    name: "Stunned",
    effects: [
      "Is Incapacitated, can't move, and can speak only falteringly.",
      "Automatically fails Strength and Dexterity saving throws.",
      "Attack rolls against the creature have Advantage."
    ]
  },
  %{
    slug: "unconscious",
    name: "Unconscious",
    effects: [
      "Is Incapacitated, can't move or speak, and is unaware of its surroundings.",
      "Drops whatever it is holding and falls Prone.",
      "Automatically fails Strength and Dexterity saving throws.",
      "Attack rolls against the creature have Advantage.",
      "Any attack that hits it is a critical hit if the attacker is within 5 feet."
    ]
  }
]
