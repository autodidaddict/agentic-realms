# SRD 5.2 classes. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD classes section:
# https://5e24srd.com/classes/index.html
#
# The twelve classes of the SRD. Each carries its core traits, every choice it
# asks the character to make, and the features it grants at each level. Feature
# text is a concise restatement of the mechanics, not verbatim SRD prose.
#
# The class features table also has "Subclass feature" rows at the levels where
# a subclass grants something. Those are not class features and are not repeated
# here; they come from `Srd.Content.Subclasses.for_class/1`.
#
# Spells are not part of this package. Classes that cast record how they cast in
# `spellcasting` and name spells in feature text without resolving them.
[
  %{
    slug: "barbarian",
    name: "Barbarian",
    primary_ability: {:all, [:str]},
    hit_die: "1d12",
    saving_throws: [:str, :con],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:animal_handling, :athletics, :intimidation, :nature, :perception, :survival]
    },
    weapon_proficiencies: [:simple, :martial],
    armor_training: [:light, :medium, :shield],
    subclass_level: 3,
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{items: ["greataxe", {"handaxe", 4}, "explorers-pack"], gp: 15},
        %{items: [], gp: 75}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Rage",
        text:
          "As a bonus action while not in heavy armor, enter a rage for the uses shown at your " <>
            "level. Regain one use on a short rest and all of them on a long rest."
      },
      %{
        level: 1,
        name: "Unarmored Defense",
        text:
          "While wearing no armor, your base Armor Class is 10 plus your Dexterity and " <>
            "Constitution modifiers. A shield still applies."
      },
      %{
        level: 1,
        name: "Weapon Mastery",
        text:
          "Use the mastery properties of two kinds of simple or martial melee weapons, swapping " <>
            "one on each long rest. The number rises at higher levels.",
        choice: %{kind: :weapon, choose: 2, from: {:weapons, kind: :melee}}
      },
      %{
        level: 2,
        name: "Danger Sense",
        text: "You have advantage on Dexterity saving throws unless you are incapacitated."
      },
      %{
        level: 2,
        name: "Reckless Attack",
        text:
          "On your first attack roll of your turn, choose to attack recklessly: Strength attack " <>
            "rolls have advantage until your next turn, and attacks against you do too."
      },
      %{
        level: 3,
        name: "Barbarian Subclass",
        text: "Choose a barbarian subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 3,
        name: "Primal Knowledge",
        text:
          "Gain proficiency in another barbarian skill. While raging, you can make Acrobatics, " <>
            "Intimidation, Perception, Stealth, and Survival checks as Strength checks.",
        choice: %{
          kind: :skill,
          choose: 1,
          from: [:animal_handling, :athletics, :intimidation, :nature, :perception, :survival]
        }
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Extra Attack",
        text: "Attack twice instead of once when you take the Attack action."
      },
      %{level: 5, name: "Fast Movement", text: "Your speed increases by 10 feet out of heavy armor."},
      %{level: 7, name: "Feral Instinct", text: "You have advantage on initiative rolls."},
      %{
        level: 7,
        name: "Instinctive Pounce",
        text: "As part of the bonus action to enter your rage, move up to half your speed."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 9,
        name: "Brutal Strike",
        text:
          "When using Reckless Attack, forgo advantage on one Strength attack roll to deal an " <>
            "extra 1d10 damage and apply one Brutal Strike effect on a hit."
      },
      %{
        level: 11,
        name: "Relentless Rage",
        text:
          "When you drop to 0 hit points while raging, make a DC 10 Constitution save to drop " <>
            "to twice your barbarian level instead. The DC rises by 5 each use and resets on a rest."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 13,
        name: "Improved Brutal Strike",
        text: "Staggering Blow joins your Brutal Strike options."
      },
      %{
        level: 15,
        name: "Persistent Rage",
        text:
          "On initiative, regain all uses of Rage, once per long rest. Your rage lasts 10 " <>
            "minutes without needing to be extended."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 17,
        name: "Improved Brutal Strike",
        text: "Brutal Strike's extra damage rises to 2d10, and you can use two effects at once."
      },
      %{
        level: 18,
        name: "Indomitable Might",
        text:
          "If a Strength check or save totals less than your Strength score, use the score instead."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Primal Champion",
        text: "Your Strength and Constitution scores increase by 4, to a maximum of 25."
      }
    ]
  },
  %{
    slug: "bard",
    name: "Bard",
    primary_ability: {:all, [:cha]},
    hit_die: "1d8",
    saving_throws: [:dex, :cha],
    skill_choice: %{
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
    },
    weapon_proficiencies: [:simple],
    armor_training: [:light],
    tool_proficiency: %{kind: :tool, choose: 3, from: {:items, :musical_instrument}},
    subclass_level: 3,
    spellcasting: %{ability: :cha, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: ["leather", {"dagger", 2}, "entertainers-pack"],
          choices: [%{kind: :tool, choose: 1, from: {:items, :musical_instrument}}],
          gp: 19
        },
        %{items: [], gp: 90}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Bardic Inspiration",
        text:
          "As a bonus action, give a creature within 60 feet a Bardic Inspiration die, starting " <>
            "at a d6. A creature can hold only one at a time."
      },
      %{
        level: 1,
        name: "Spellcasting",
        text:
          "Cast bard spells using Charisma, knowing two cantrips and preparing spells as the " <>
            "class table shows."
      },
      %{
        level: 2,
        name: "Expertise",
        text: "Gain expertise in two of your skill proficiencies."
      },
      %{
        level: 2,
        name: "Jack of All Trades",
        text:
          "Add half your proficiency bonus, rounded down, to ability checks using skills you " <>
            "lack proficiency in."
      },
      %{
        level: 3,
        name: "Bard Subclass",
        text: "Choose a bard subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Font of Inspiration",
        text:
          "Regain all uses of Bardic Inspiration on a short or long rest, and expend a spell " <>
            "slot to regain one."
      },
      %{
        level: 7,
        name: "Countercharm",
        text:
          "As a reaction when you or a creature within 30 feet fails a save against being " <>
            "charmed or frightened, reroll the save with advantage."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{level: 9, name: "Expertise", text: "Gain expertise in two more of your skill proficiencies."},
      %{
        level: 10,
        name: "Magical Secrets",
        text:
          "New prepared spells can come from the bard, cleric, druid, and wizard lists, and " <>
            "count as bard spells for you."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 18,
        name: "Superior Inspiration",
        text: "On initiative, regain uses of Bardic Inspiration until you have two."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Words of Creation",
        text:
          "Always have Power Word Heal and Power Word Kill prepared, and each can target a " <>
            "second creature within 10 feet of the first."
      }
    ]
  },
  %{
    slug: "cleric",
    name: "Cleric",
    primary_ability: {:all, [:wis]},
    hit_die: "1d8",
    saving_throws: [:wis, :cha],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:history, :insight, :medicine, :persuasion, :religion]
    },
    weapon_proficiencies: [:simple],
    armor_training: [:light, :medium, :shield],
    subclass_level: 3,
    spellcasting: %{ability: :wis, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{items: ["chain-shirt", "shield", "mace", "holy-symbol", "priests-pack"], gp: 7},
        %{items: [], gp: 110}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Spellcasting",
        text:
          "Cast cleric spells using Wisdom, knowing three cantrips and preparing spells as the " <>
            "class table shows."
      },
      %{
        level: 1,
        name: "Divine Order",
        text:
          "Choose a sacred role: Protector grants martial weapon proficiency and heavy armor " <>
            "training; Thaumaturge grants an extra cantrip and a bonus to Arcana and Religion checks.",
        choice: %{kind: :feature, choose: 1, from: ["Protector", "Thaumaturge"]}
      },
      %{
        level: 2,
        name: "Channel Divinity",
        text:
          "Fuel divine effects, starting with Divine Spark and Turn Undead. Two uses, one back " <>
            "on a short rest and all on a long rest; more uses at higher levels."
      },
      %{
        level: 3,
        name: "Cleric Subclass",
        text: "Choose a cleric subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Sear Undead",
        text:
          "When you use Turn Undead, roll d8s equal to your Wisdom modifier; undead that fail " <>
            "the save take that much radiant damage."
      },
      %{
        level: 7,
        name: "Blessed Strikes",
        text:
          "Choose Divine Strike, adding 1d8 necrotic or radiant damage once per turn on a " <>
            "weapon hit, or Potent Spellcasting, adding your Wisdom modifier to cantrip damage.",
        choice: %{kind: :feature, choose: 1, from: ["Divine Strike", "Potent Spellcasting"]}
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 10,
        name: "Divine Intervention",
        text:
          "As a magic action, cast any cleric spell of level 5 or lower without a slot or " <>
            "material components. Once per long rest."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 14,
        name: "Improved Blessed Strikes",
        text: "Your Blessed Strikes option grows stronger."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Greater Divine Intervention",
        text: "Divine Intervention can cast Wish, after which it recharges over 2d4 long rests."
      }
    ]
  },
  %{
    slug: "druid",
    name: "Druid",
    primary_ability: {:all, [:wis]},
    hit_die: "1d8",
    saving_throws: [:int, :wis],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [
        :animal_handling,
        :arcana,
        :insight,
        :medicine,
        :nature,
        :perception,
        :religion,
        :survival
      ]
    },
    weapon_proficiencies: [:simple],
    armor_training: [:light, :shield],
    tool_proficiency: %{kind: :tool, choose: 1, from: ["herbalism-kit"]},
    subclass_level: 3,
    spellcasting: %{ability: :wis, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "leather",
            "shield",
            "sickle",
            %{item: "druidic-focus", quantity: 1, variant: "Wooden staff"},
            "explorers-pack",
            "herbalism-kit"
          ],
          gp: 9
        },
        %{items: [], gp: 50}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Spellcasting",
        text:
          "Cast druid spells using Wisdom, knowing two cantrips and preparing spells as the " <>
            "class table shows."
      },
      %{
        level: 1,
        name: "Druidic",
        text:
          "You know Druidic and always have Speak with Animals prepared. Hidden Druidic messages " <>
            "are spotted with a DC 15 Investigation check but need magic to read."
      },
      %{
        level: 1,
        name: "Primal Order",
        text:
          "Choose a role: Magician grants an extra cantrip and a bonus to Arcana and Nature " <>
            "checks; Warden grants martial weapon proficiency and medium armor training.",
        choice: %{kind: :feature, choose: 1, from: ["Magician", "Warden"]}
      },
      %{
        level: 2,
        name: "Wild Shape",
        text:
          "As a bonus action, take a known beast form for hours equal to half your druid level. " <>
            "Two uses, one back on a short rest and all on a long rest."
      },
      %{
        level: 2,
        name: "Wild Companion",
        text:
          "Expend a spell slot or a use of Wild Shape to cast Find Familiar without material " <>
            "components; the familiar is fey and lasts until your next long rest."
      },
      %{
        level: 3,
        name: "Druid Subclass",
        text: "Choose a druid subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Wild Resurgence",
        text:
          "Once per turn, spend a spell slot to regain a use of Wild Shape, or spend a use of " <>
            "Wild Shape for a level 1 slot once per long rest."
      },
      %{
        level: 7,
        name: "Elemental Fury",
        text:
          "Choose Potent Spellcasting, adding your Wisdom modifier to druid cantrip damage, or " <>
            "Primal Strike, adding 1d8 elemental damage once per turn.",
        choice: %{kind: :feature, choose: 1, from: ["Potent Spellcasting", "Primal Strike"]}
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 15,
        name: "Improved Elemental Fury",
        text: "Your Elemental Fury option grows stronger."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 18,
        name: "Beast Spells",
        text:
          "Cast spells in beast form, except those with a costly or consumed material component."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Archdruid",
        text:
          "Regain a use of Wild Shape on initiative when you have none, among other lasting " <>
            "benefits of nature's vitality."
      }
    ]
  },
  %{
    slug: "fighter",
    name: "Fighter",
    primary_ability: {:any, [:str, :dex]},
    hit_die: "1d10",
    saving_throws: [:str, :con],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [
        :acrobatics,
        :animal_handling,
        :athletics,
        :history,
        :insight,
        :intimidation,
        :perception,
        :persuasion,
        :survival
      ]
    },
    weapon_proficiencies: [:simple, :martial],
    armor_training: [:light, :medium, :heavy, :shield],
    subclass_level: 3,
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: ["chain-mail", "greatsword", "flail", {"javelin", 8}, "dungeoneers-pack"],
          gp: 4
        },
        %{
          items: [
            "studded-leather",
            "scimitar",
            "shortsword",
            "longbow",
            {"arrows", 20},
            "quiver",
            "dungeoneers-pack"
          ],
          gp: 11
        },
        %{items: [], gp: 155}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Fighting Style",
        text:
          "Gain a Fighting Style feat, which you can swap for another whenever you gain a " <>
            "fighter level.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :fighting_style}}
      },
      %{
        level: 1,
        name: "Second Wind",
        text:
          "As a bonus action, regain 1d10 plus your fighter level in hit points. Two uses, one " <>
            "back on a short rest and all on a long rest."
      },
      %{
        level: 1,
        name: "Weapon Mastery",
        text:
          "Use the mastery properties of three kinds of simple or martial weapons, swapping one " <>
            "on each long rest. The number rises at higher levels.",
        choice: %{kind: :weapon, choose: 3, from: {:weapons, []}}
      },
      %{
        level: 2,
        name: "Action Surge",
        text:
          "Take one additional action on your turn, except the Magic action. Once per short or " <>
            "long rest, twice from level 17."
      },
      %{
        level: 2,
        name: "Tactical Mind",
        text:
          "When you fail an ability check, expend a use of Second Wind to add 1d10 to it. The " <>
            "use isn't spent if the check still fails."
      },
      %{
        level: 3,
        name: "Fighter Subclass",
        text: "Choose a fighter subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Extra Attack",
        text: "Attack twice instead of once when you take the Attack action."
      },
      %{
        level: 5,
        name: "Tactical Shift",
        text:
          "When you activate Second Wind as a bonus action, move up to half your speed without " <>
            "provoking opportunity attacks."
      },
      %{
        level: 6,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 9,
        name: "Indomitable",
        text:
          "Reroll a failed saving throw with a bonus equal to your fighter level. Once per long " <>
            "rest, twice from level 13 and three times from level 17."
      },
      %{
        level: 9,
        name: "Tactical Master",
        text:
          "When attacking with a weapon whose mastery you can use, swap that property for Push, " <>
            "Sap, or Slow."
      },
      %{
        level: 11,
        name: "Two Extra Attacks",
        text: "Attack three times instead of once when you take the Attack action."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 13,
        name: "Studied Attacks",
        text:
          "When you miss a creature with an attack roll, you have advantage on your next attack " <>
            "roll against it before the end of your next turn."
      },
      %{
        level: 14,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Three Extra Attacks",
        text: "Attack four times instead of once when you take the Attack action."
      }
    ]
  },
  %{
    slug: "monk",
    name: "Monk",
    primary_ability: {:all, [:dex, :wis]},
    hit_die: "1d8",
    saving_throws: [:str, :dex],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:acrobatics, :athletics, :history, :insight, :religion, :stealth]
    },
    weapon_proficiencies: [:simple, {:martial, [:light]}],
    armor_training: [],
    tool_proficiency: %{kind: :tool, choose: 1, from: {:items, :artisans_tools}},
    subclass_level: 3,
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: ["spear", {"dagger", 5}, "explorers-pack"],
          # The same kind of tool chosen for the tool proficiency above.
          choices: [%{kind: :tool, choose: 1, from: {:items, :artisans_tools}}],
          gp: 11
        },
        %{items: [], gp: 50}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Martial Arts",
        text:
          "With unarmed strikes and monk weapons - simple melee weapons and light martial melee " <>
            "weapons - use Dexterity, roll the Martial Arts die for damage, and make an unarmed " <>
            "strike as a bonus action."
      },
      %{
        level: 1,
        name: "Unarmored Defense",
        text:
          "While wearing no armor and no shield, your base Armor Class is 10 plus your " <>
            "Dexterity and Wisdom modifiers."
      },
      %{
        level: 2,
        name: "Monk's Focus",
        text:
          "Spend focus points to fuel Flurry of Blows, Patient Defense, and Step of the Wind. " <>
            "Points equal the class table's total for your level."
      },
      %{
        level: 2,
        name: "Unarmored Movement",
        text: "Your speed increases by 10 feet while wearing no armor and no shield, rising with level."
      },
      %{
        level: 2,
        name: "Uncanny Metabolism",
        text:
          "On initiative, regain all focus points and heal your monk level plus a Martial Arts " <>
            "die. Once per long rest."
      },
      %{
        level: 3,
        name: "Deflect Attacks",
        text:
          "As a reaction to an attack that deals bludgeoning, piercing, or slashing damage, " <>
            "reduce it by 1d10 plus your Dexterity modifier and monk level, and spend 1 focus " <>
            "point to redirect it."
      },
      %{
        level: 3,
        name: "Monk Subclass",
        text: "Choose a monk subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 4,
        name: "Slow Fall",
        text: "As a reaction when you fall, reduce the damage by five times your monk level."
      },
      %{
        level: 5,
        name: "Extra Attack",
        text: "Attack twice instead of once when you take the Attack action."
      },
      %{
        level: 5,
        name: "Stunning Strike",
        text:
          "Once per turn on a hit, spend 1 focus point to force a Constitution save; on a " <>
            "failure the target is stunned until the start of your next turn."
      },
      %{
        level: 6,
        name: "Empowered Strikes",
        text: "Your unarmed strikes can deal force damage instead of their normal type."
      },
      %{
        level: 7,
        name: "Evasion",
        text:
          "On a Dexterity save for half damage, take none on a success and half on a failure, " <>
            "unless incapacitated."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 9,
        name: "Acrobatic Movement",
        text:
          "While wearing no armor and no shield, move along vertical surfaces and across " <>
            "liquids without falling."
      },
      %{
        level: 10,
        name: "Heightened Focus",
        text: "Flurry of Blows, Patient Defense, and Step of the Wind each gain an added benefit."
      },
      %{
        level: 10,
        name: "Self-Restoration",
        text:
          "At the end of each of your turns, end one of charmed, frightened, or poisoned on " <>
            "yourself. Going without food or drink no longer causes exhaustion."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 13,
        name: "Deflect Energy",
        text: "Deflect Attacks now works against any damage type."
      },
      %{
        level: 14,
        name: "Disciplined Survivor",
        text:
          "You are proficient in all saving throws, and can spend 1 focus point to reroll a " <>
            "failed one."
      },
      %{
        level: 15,
        name: "Perfect Focus",
        text:
          "On initiative without using Uncanny Metabolism, regain focus points until you have four."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 18,
        name: "Superior Defense",
        text:
          "At the start of your turn, spend 3 focus points for resistance to all damage except " <>
            "force for 1 minute."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Body and Mind",
        text: "Your Dexterity and Wisdom scores increase by 4, to a maximum of 25."
      }
    ]
  },
  %{
    slug: "paladin",
    name: "Paladin",
    primary_ability: {:all, [:str, :cha]},
    hit_die: "1d10",
    saving_throws: [:wis, :cha],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:athletics, :insight, :intimidation, :medicine, :persuasion, :religion]
    },
    weapon_proficiencies: [:simple, :martial],
    armor_training: [:light, :medium, :heavy, :shield],
    subclass_level: 3,
    spellcasting: %{ability: :cha, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: ["chain-mail", "shield", "longsword", {"javelin", 6}, "holy-symbol", "priests-pack"],
          gp: 9
        },
        %{items: [], gp: 150}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Lay On Hands",
        text:
          "A healing pool of five times your paladin level, spent as a bonus action by touch and " <>
            "replenished on a long rest."
      },
      %{
        level: 1,
        name: "Spellcasting",
        text: "Cast paladin spells using Charisma, preparing spells as the class table shows."
      },
      %{
        level: 1,
        name: "Weapon Mastery",
        text:
          "Use the mastery properties of two kinds of weapons you are proficient with, changing " <>
            "them on each long rest.",
        choice: %{kind: :weapon, choose: 2, from: {:weapons, []}}
      },
      %{
        level: 2,
        name: "Fighting Style",
        text:
          "Gain a Fighting Style feat, or take Blessed Warrior to learn two cleric cantrips cast " <>
            "with Charisma.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :fighting_style}}
      },
      %{
        level: 2,
        name: "Paladin's Smite",
        text:
          "Always have Divine Smite prepared, and cast it once without a slot per long rest."
      },
      %{
        level: 3,
        name: "Channel Divinity",
        text:
          "Fuel divine effects, starting with Divine Sense. Two uses, one back on a short rest " <>
            "and all on a long rest."
      },
      %{
        level: 3,
        name: "Paladin Subclass",
        text: "Choose a paladin subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Extra Attack",
        text: "Attack twice instead of once when you take the Attack action."
      },
      %{
        level: 5,
        name: "Faithful Steed",
        text: "Always have Find Steed prepared, and cast it once without a slot per long rest."
      },
      %{
        level: 6,
        name: "Aura of Protection",
        text:
          "You and allies within 10 feet gain a bonus to saving throws equal to your Charisma " <>
            "modifier, minimum +1. Inactive while you are incapacitated."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 9,
        name: "Abjure Foes",
        text:
          "Spend a use of Channel Divinity to frighten creatures within 60 feet, up to your " <>
            "Charisma modifier, on a failed Wisdom save."
      },
      %{
        level: 10,
        name: "Aura of Courage",
        text: "You and allies in your aura are immune to the frightened condition."
      },
      %{
        level: 11,
        name: "Radiant Strikes",
        text: "Your melee weapon and unarmed strike hits deal an extra 1d8 radiant damage."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 14,
        name: "Restoring Touch",
        text:
          "Lay On Hands can also end blinded, charmed, deafened, frightened, paralyzed, or " <>
            "stunned, at 5 hit points from the pool per condition."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{level: 18, name: "Aura Expansion", text: "Your Aura of Protection reaches 30 feet."},
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      }
    ]
  },
  %{
    slug: "ranger",
    name: "Ranger",
    primary_ability: {:all, [:dex, :wis]},
    hit_die: "1d10",
    saving_throws: [:str, :dex],
    skill_choice: %{
      kind: :skill,
      choose: 3,
      from: [
        :animal_handling,
        :athletics,
        :insight,
        :investigation,
        :nature,
        :perception,
        :stealth,
        :survival
      ]
    },
    weapon_proficiencies: [:simple, :martial],
    armor_training: [:light, :medium, :shield],
    subclass_level: 3,
    spellcasting: %{ability: :wis, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "studded-leather",
            "scimitar",
            "shortsword",
            "longbow",
            {"arrows", 20},
            "quiver",
            %{item: "druidic-focus", quantity: 1, variant: "Sprig of mistletoe"},
            "explorers-pack"
          ],
          gp: 7
        },
        %{items: [], gp: 150}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Spellcasting",
        text: "Cast ranger spells using Wisdom, preparing spells as the class table shows."
      },
      %{
        level: 1,
        name: "Favored Enemy",
        text:
          "Always have Hunter's Mark prepared and cast it without a slot the number of times " <>
            "shown for your level, regained on a long rest."
      },
      %{
        level: 1,
        name: "Weapon Mastery",
        text:
          "Use the mastery properties of two kinds of weapons you are proficient with, changing " <>
            "them on each long rest.",
        choice: %{kind: :weapon, choose: 2, from: {:weapons, []}}
      },
      %{
        level: 2,
        name: "Deft Explorer",
        text: "Gain expertise in one of your skill proficiencies, and learn two languages."
      },
      %{
        level: 2,
        name: "Fighting Style",
        text:
          "Gain a Fighting Style feat, or take Druidic Warrior to learn two druid cantrips cast " <>
            "with Wisdom.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :fighting_style}}
      },
      %{
        level: 3,
        name: "Ranger Subclass",
        text: "Choose a ranger subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Extra Attack",
        text: "Attack twice instead of once when you take the Attack action."
      },
      %{
        level: 6,
        name: "Roving",
        text:
          "Your speed increases by 10 feet out of heavy armor, and you gain a climb speed and a " <>
            "swim speed equal to your speed."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{level: 9, name: "Expertise", text: "Gain expertise in two more of your skill proficiencies."},
      %{
        level: 10,
        name: "Tireless",
        text:
          "As a magic action, give yourself 1d8 plus your Wisdom modifier in temporary hit " <>
            "points, and reduce exhaustion on a short rest."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 13,
        name: "Relentless Hunter",
        text: "Taking damage can't break your concentration on Hunter's Mark."
      },
      %{
        level: 14,
        name: "Nature's Veil",
        text:
          "As a bonus action, become invisible until the end of your next turn, a number of " <>
            "times equal to your Wisdom modifier per long rest."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 17,
        name: "Precise Hunter",
        text: "You have advantage on attack rolls against the creature marked by your Hunter's Mark."
      },
      %{level: 18, name: "Feral Senses", text: "You have blindsight out to 30 feet."},
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{level: 20, name: "Foe Slayer", text: "Your Hunter's Mark damage die becomes a d10."}
    ]
  },
  %{
    slug: "rogue",
    name: "Rogue",
    primary_ability: {:all, [:dex]},
    hit_die: "1d8",
    saving_throws: [:dex, :int],
    skill_choice: %{
      kind: :skill,
      choose: 4,
      from: [
        :acrobatics,
        :athletics,
        :deception,
        :insight,
        :intimidation,
        :investigation,
        :perception,
        :persuasion,
        :sleight_of_hand,
        :stealth
      ]
    },
    weapon_proficiencies: [:simple, {:martial, [:finesse, :light]}],
    armor_training: [:light],
    tool_proficiency: %{kind: :tool, choose: 1, from: ["thieves-tools"]},
    subclass_level: 3,
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "leather",
            {"dagger", 2},
            "shortsword",
            "shortbow",
            {"arrows", 20},
            "quiver",
            "thieves-tools",
            "burglars-pack"
          ],
          gp: 8
        },
        %{items: [], gp: 100}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Expertise",
        text: "Gain expertise in two of your skill proficiencies."
      },
      %{
        level: 1,
        name: "Sneak Attack",
        text:
          "Once per turn, deal an extra 1d6 damage to a creature you hit with a finesse or " <>
            "ranged weapon while you have advantage, or while an ally is within 5 feet of it " <>
            "and you lack disadvantage. The damage rises with level."
      },
      %{
        level: 1,
        name: "Thieves' Cant",
        text: "You know Thieves' Cant and one other language of your choice."
      },
      %{
        level: 1,
        name: "Weapon Mastery",
        text:
          "Use the mastery properties of two kinds of weapons you are proficient with, changing " <>
            "them on each long rest.",
        choice: %{kind: :weapon, choose: 2, from: {:weapons, []}}
      },
      %{
        level: 2,
        name: "Cunning Action",
        text: "Take the Dash, Disengage, or Hide action as a bonus action."
      },
      %{
        level: 3,
        name: "Rogue Subclass",
        text: "Choose a rogue subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 3,
        name: "Steady Aim",
        text:
          "As a bonus action, gain advantage on your next attack roll this turn if you haven't " <>
            "moved; your speed is then 0 for the turn."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Cunning Strike",
        text:
          "Forgo Sneak Attack dice to add effects such as Poison, Trip, or Withdraw, each with " <>
            "its own die cost."
      },
      %{
        level: 5,
        name: "Uncanny Dodge",
        text: "As a reaction to a visible attacker's hit, halve the damage against you."
      },
      %{level: 6, name: "Expertise", text: "Gain expertise in two more of your skill proficiencies."},
      %{
        level: 7,
        name: "Evasion",
        text:
          "On a Dexterity save for half damage, take none on a success and half on a failure, " <>
            "unless incapacitated."
      },
      %{
        level: 7,
        name: "Reliable Talent",
        text: "On checks using your skill or tool proficiencies, treat a d20 roll of 9 or lower as 10."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 10,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 11,
        name: "Improved Cunning Strike",
        text: "Use up to two Cunning Strike effects at once, paying each die cost."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 14,
        name: "Devious Strikes",
        text: "Daze, Knock Out, and Obscure join your Cunning Strike options."
      },
      %{
        level: 15,
        name: "Slippery Mind",
        text: "You gain proficiency in Wisdom and Charisma saving throws."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 18,
        name: "Elusive",
        text: "No attack roll has advantage against you unless you are incapacitated."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Stroke of Luck",
        text: "Turn a failed d20 test into a 20. Once per short or long rest."
      }
    ]
  },
  %{
    slug: "sorcerer",
    name: "Sorcerer",
    primary_ability: {:all, [:cha]},
    hit_die: "1d6",
    saving_throws: [:con, :cha],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:arcana, :deception, :insight, :intimidation, :persuasion, :religion]
    },
    weapon_proficiencies: [:simple],
    armor_training: [],
    subclass_level: 3,
    spellcasting: %{ability: :cha, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "spear",
            {"dagger", 2},
            %{item: "arcane-focus", quantity: 1, variant: "Crystal"},
            "dungeoneers-pack"
          ],
          gp: 28
        },
        %{items: [], gp: 50}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Spellcasting",
        text:
          "Cast sorcerer spells using Charisma, knowing four cantrips and preparing spells as " <>
            "the class table shows."
      },
      %{
        level: 1,
        name: "Innate Sorcery",
        text:
          "As a bonus action for 1 minute, raise your sorcerer spell save DC by 1 and gain " <>
            "advantage on sorcerer spell attack rolls. Twice per long rest."
      },
      %{
        level: 2,
        name: "Font of Magic",
        text:
          "Sorcery points, equal to the class table's total for your level, regained on a long rest."
      },
      %{
        level: 2,
        name: "Metamagic",
        text:
          "Gain two Metamagic options, spending sorcery points to modify a spell as you cast it.",
        choice: %{
          kind: :feature,
          choose: 2,
          from: [
            "Careful Spell",
            "Distant Spell",
            "Empowered Spell",
            "Extended Spell",
            "Heightened Spell",
            "Quickened Spell",
            "Seeking Spell",
            "Subtle Spell",
            "Transmuted Spell",
            "Twinned Spell"
          ]
        }
      },
      %{
        level: 3,
        name: "Sorcerer Subclass",
        text: "Choose a sorcerer subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Sorcerous Restoration",
        text:
          "On a short rest, regain sorcery points up to half your sorcerer level. Once per long rest."
      },
      %{
        level: 7,
        name: "Sorcery Incarnate",
        text:
          "Spend 2 sorcery points to use Innate Sorcery with no uses left, and use two Metamagic " <>
            "options per spell while it is active."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{level: 10, name: "Metamagic", text: "Gain two more Metamagic options."},
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{level: 17, name: "Metamagic", text: "Gain two more Metamagic options."},
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Arcane Apotheosis",
        text:
          "While Innate Sorcery is active, use one Metamagic option each turn without spending " <>
            "sorcery points."
      }
    ]
  },
  %{
    slug: "warlock",
    name: "Warlock",
    primary_ability: {:all, [:cha]},
    hit_die: "1d8",
    saving_throws: [:wis, :cha],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:arcana, :deception, :history, :intimidation, :investigation, :nature, :religion]
    },
    weapon_proficiencies: [:simple],
    armor_training: [:light],
    subclass_level: 3,
    spellcasting: %{ability: :cha, kind: :pact},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            "leather",
            "sickle",
            {"dagger", 2},
            %{item: "arcane-focus", quantity: 1, variant: "Orb"},
            %{item: "book", quantity: 1, variant: "Occult lore"},
            "scholars-pack"
          ],
          gp: 15
        },
        %{items: [], gp: 100}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Eldritch Invocations",
        text:
          "Gain one Eldritch Invocation, meeting any prerequisite. You learn more and can swap " <>
            "them as you gain levels."
      },
      %{
        level: 1,
        name: "Pact Magic",
        text:
          "Cast warlock spells using Charisma, knowing two cantrips. Your pact slots are all of " <>
            "the same level and return on a short rest."
      },
      %{
        level: 2,
        name: "Magical Cunning",
        text:
          "Spend 1 minute on a rite to regain up to half your pact magic slots. Once per long rest."
      },
      %{
        level: 3,
        name: "Warlock Subclass",
        text: "Choose a warlock subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 9,
        name: "Contact Patron",
        text:
          "Always have Contact Other Plane prepared, cast without a slot to reach your patron " <>
            "and automatically succeed on its save. Once per long rest."
      },
      %{
        level: 11,
        name: "Mystic Arcanum",
        text: "Choose a level 6 warlock spell, cast once without a slot per long rest."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 13,
        name: "Mystic Arcanum",
        text: "Choose a level 7 warlock spell, cast once without a slot per long rest."
      },
      %{
        level: 15,
        name: "Mystic Arcanum",
        text: "Choose a level 8 warlock spell, cast once without a slot per long rest."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 17,
        name: "Mystic Arcanum",
        text: "Choose a level 9 warlock spell, cast once without a slot per long rest."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Eldritch Master",
        text: "Magical Cunning restores all of your expended pact magic slots."
      }
    ]
  },
  %{
    slug: "wizard",
    name: "Wizard",
    primary_ability: {:all, [:int]},
    hit_die: "1d6",
    saving_throws: [:int, :wis],
    skill_choice: %{
      kind: :skill,
      choose: 2,
      from: [:arcana, :history, :insight, :investigation, :medicine, :nature, :religion]
    },
    weapon_proficiencies: [:simple],
    armor_training: [],
    subclass_level: 3,
    spellcasting: %{ability: :int, kind: :prepared},
    starting_equipment: %{
      kind: :equipment,
      choose: 1,
      from: [
        %{
          items: [
            {"dagger", 2},
            %{item: "arcane-focus", quantity: 1, variant: "Staff"},
            "robe",
            "spellbook",
            "scholars-pack"
          ],
          gp: 5
        },
        %{items: [], gp: 55}
      ]
    },
    features: [
      %{
        level: 1,
        name: "Spellcasting",
        text:
          "Cast wizard spells using Intelligence, knowing three cantrips and preparing spells " <>
            "from your spellbook as the class table shows."
      },
      %{
        level: 1,
        name: "Ritual Adept",
        text:
          "Cast any spell with the Ritual tag from your spellbook as a ritual, without preparing it."
      },
      %{
        level: 1,
        name: "Arcane Recovery",
        text:
          "On a short rest, recover spell slots totaling up to half your wizard level, none " <>
            "above level 5. Once per long rest."
      },
      %{
        level: 2,
        name: "Scholar",
        text: "Gain expertise in one of Arcana, History, Investigation, Medicine, Nature, or Religion.",
        choice: %{
          kind: :skill,
          choose: 1,
          from: [:arcana, :history, :investigation, :medicine, :nature, :religion]
        }
      },
      %{
        level: 3,
        name: "Wizard Subclass",
        text: "Choose a wizard subclass; see `Srd.Content.Subclasses.for_class/1`."
      },
      %{
        level: 4,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 5,
        name: "Memorize Spell",
        text:
          "On a short rest, swap one prepared level 1+ wizard spell for another from your spellbook."
      },
      %{
        level: 8,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 12,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 16,
        name: "Ability Score Improvement",
        text: "Gain the Ability Score Improvement feat or another feat you qualify for."
      },
      %{
        level: 18,
        name: "Spell Mastery",
        text:
          "Choose a level 1 and a level 2 spell in your spellbook; cast them at their lowest " <>
            "level without expending a slot."
      },
      %{
        level: 19,
        name: "Epic Boon",
        text: "Gain an Epic Boon feat or another feat you qualify for.",
        choice: %{kind: :feat, choose: 1, from: {:feats, :epic_boon}}
      },
      %{
        level: 20,
        name: "Signature Spells",
        text:
          "Choose two level 3 spells in your spellbook; always have them prepared and cast each " <>
            "once per short or long rest without a slot."
      }
    ]
  }
]
