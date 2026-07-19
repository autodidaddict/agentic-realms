# SRD 5.2 weapons. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD weapons table:
# https://5e24srd.com/equipment/weapons.html
#
# Each entry becomes a Srd.Content.Weapon at compile time: `damage`/`versatile`
# are dice-notation strings parsed into Srd.Dice.Expr, `damage_type` is validated
# against Srd.Rules.Damage.types/0, and `mastery` against the weapon masteries.
#
# The Blowgun deals a flat 1 damage (no die); it's encoded as "1d1", which always
# rolls 1. Range, cost, and weight are not modeled yet.
[
  # --- Simple melee ---
  %{slug: "club", name: "Club", category: :simple, kind: :melee, damage: "1d4", damage_type: :bludgeoning, properties: [:light], mastery: :slow},
  %{slug: "dagger", name: "Dagger", category: :simple, kind: :melee, damage: "1d4", damage_type: :piercing, properties: [:finesse, :light, :thrown], mastery: :nick},
  %{slug: "greatclub", name: "Greatclub", category: :simple, kind: :melee, damage: "1d8", damage_type: :bludgeoning, properties: [:two_handed], mastery: :push},
  %{slug: "handaxe", name: "Handaxe", category: :simple, kind: :melee, damage: "1d6", damage_type: :slashing, properties: [:light, :thrown], mastery: :vex},
  %{slug: "javelin", name: "Javelin", category: :simple, kind: :melee, damage: "1d6", damage_type: :piercing, properties: [:thrown], mastery: :slow},
  %{slug: "light-hammer", name: "Light Hammer", category: :simple, kind: :melee, damage: "1d4", damage_type: :bludgeoning, properties: [:light, :thrown], mastery: :nick},
  %{slug: "mace", name: "Mace", category: :simple, kind: :melee, damage: "1d6", damage_type: :bludgeoning, properties: [], mastery: :sap},
  %{slug: "quarterstaff", name: "Quarterstaff", category: :simple, kind: :melee, damage: "1d6", damage_type: :bludgeoning, versatile: "1d8", properties: [:versatile], mastery: :topple},
  %{slug: "sickle", name: "Sickle", category: :simple, kind: :melee, damage: "1d4", damage_type: :slashing, properties: [:light], mastery: :nick},
  %{slug: "spear", name: "Spear", category: :simple, kind: :melee, damage: "1d6", damage_type: :piercing, versatile: "1d8", properties: [:thrown, :versatile], mastery: :sap},

  # --- Simple ranged ---
  %{slug: "dart", name: "Dart", category: :simple, kind: :ranged, damage: "1d4", damage_type: :piercing, properties: [:finesse, :thrown], mastery: :vex},
  %{slug: "light-crossbow", name: "Light Crossbow", category: :simple, kind: :ranged, damage: "1d8", damage_type: :piercing, properties: [:ammunition, :loading, :two_handed], mastery: :slow},
  %{slug: "shortbow", name: "Shortbow", category: :simple, kind: :ranged, damage: "1d6", damage_type: :piercing, properties: [:ammunition, :two_handed], mastery: :vex},
  %{slug: "sling", name: "Sling", category: :simple, kind: :ranged, damage: "1d4", damage_type: :bludgeoning, properties: [:ammunition], mastery: :slow},

  # --- Martial melee ---
  %{slug: "battleaxe", name: "Battleaxe", category: :martial, kind: :melee, damage: "1d8", damage_type: :slashing, versatile: "1d10", properties: [:versatile], mastery: :topple},
  %{slug: "flail", name: "Flail", category: :martial, kind: :melee, damage: "1d8", damage_type: :bludgeoning, properties: [], mastery: :sap},
  %{slug: "glaive", name: "Glaive", category: :martial, kind: :melee, damage: "1d10", damage_type: :slashing, properties: [:heavy, :reach, :two_handed], mastery: :graze},
  %{slug: "greataxe", name: "Greataxe", category: :martial, kind: :melee, damage: "1d12", damage_type: :slashing, properties: [:heavy, :two_handed], mastery: :cleave},
  %{slug: "greatsword", name: "Greatsword", category: :martial, kind: :melee, damage: "2d6", damage_type: :slashing, properties: [:heavy, :two_handed], mastery: :graze},
  %{slug: "halberd", name: "Halberd", category: :martial, kind: :melee, damage: "1d10", damage_type: :slashing, properties: [:heavy, :reach, :two_handed], mastery: :cleave},
  %{slug: "lance", name: "Lance", category: :martial, kind: :melee, damage: "1d10", damage_type: :piercing, properties: [:heavy, :reach, :two_handed], mastery: :topple},
  %{slug: "longsword", name: "Longsword", category: :martial, kind: :melee, damage: "1d8", damage_type: :slashing, versatile: "1d10", properties: [:versatile], mastery: :sap},
  %{slug: "maul", name: "Maul", category: :martial, kind: :melee, damage: "2d6", damage_type: :bludgeoning, properties: [:heavy, :two_handed], mastery: :topple},
  %{slug: "morningstar", name: "Morningstar", category: :martial, kind: :melee, damage: "1d8", damage_type: :piercing, properties: [], mastery: :sap},
  %{slug: "pike", name: "Pike", category: :martial, kind: :melee, damage: "1d10", damage_type: :piercing, properties: [:heavy, :reach, :two_handed], mastery: :push},
  %{slug: "rapier", name: "Rapier", category: :martial, kind: :melee, damage: "1d8", damage_type: :piercing, properties: [:finesse], mastery: :vex},
  %{slug: "scimitar", name: "Scimitar", category: :martial, kind: :melee, damage: "1d6", damage_type: :slashing, properties: [:finesse, :light], mastery: :nick},
  %{slug: "shortsword", name: "Shortsword", category: :martial, kind: :melee, damage: "1d6", damage_type: :piercing, properties: [:finesse, :light], mastery: :vex},
  %{slug: "trident", name: "Trident", category: :martial, kind: :melee, damage: "1d8", damage_type: :piercing, versatile: "1d10", properties: [:thrown, :versatile], mastery: :topple},
  %{slug: "warhammer", name: "Warhammer", category: :martial, kind: :melee, damage: "1d8", damage_type: :bludgeoning, versatile: "1d10", properties: [:versatile], mastery: :push},
  %{slug: "war-pick", name: "War Pick", category: :martial, kind: :melee, damage: "1d8", damage_type: :piercing, versatile: "1d10", properties: [:versatile], mastery: :sap},
  %{slug: "whip", name: "Whip", category: :martial, kind: :melee, damage: "1d4", damage_type: :slashing, properties: [:finesse, :reach], mastery: :slow},

  # --- Martial ranged ---
  %{slug: "blowgun", name: "Blowgun", category: :martial, kind: :ranged, damage: "1d1", damage_type: :piercing, properties: [:ammunition, :loading], mastery: :vex},
  %{slug: "hand-crossbow", name: "Hand Crossbow", category: :martial, kind: :ranged, damage: "1d6", damage_type: :piercing, properties: [:ammunition, :light, :loading], mastery: :vex},
  %{slug: "heavy-crossbow", name: "Heavy Crossbow", category: :martial, kind: :ranged, damage: "1d10", damage_type: :piercing, properties: [:ammunition, :heavy, :loading, :two_handed], mastery: :push},
  %{slug: "longbow", name: "Longbow", category: :martial, kind: :ranged, damage: "1d8", damage_type: :piercing, properties: [:ammunition, :heavy, :two_handed], mastery: :slow},
  %{slug: "musket", name: "Musket", category: :martial, kind: :ranged, damage: "1d12", damage_type: :piercing, properties: [:ammunition, :loading, :two_handed], mastery: :slow},
  %{slug: "pistol", name: "Pistol", category: :martial, kind: :ranged, damage: "1d10", damage_type: :piercing, properties: [:ammunition, :loading], mastery: :vex}
]
