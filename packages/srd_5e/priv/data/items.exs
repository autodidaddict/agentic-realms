# SRD 5.2 items: tools, spellcasting focuses, equipment packs, and the
# adventuring gear that class and background starting equipment refers to. See
# the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD equipment section:
# https://5e24srd.com/equipment/index.html
#
# This is not the whole gear table. It is what starting equipment and pack
# contents name, so every equipment entry resolves to a slug. Cost and weight
# are not modeled, matching the weapon and armor content.
#
# Gaming sets and musical instruments are individual items rather than one item
# with variants, because a character chooses a specific kind and the choice is
# expressed as a list of slugs. Spellcasting focuses keep their forms in
# `variants`, because the form is flavor rather than a separate proficiency.
[
  # --- Artisan's Tools ---
  %{slug: "alchemists-supplies", name: "Alchemist's Supplies", category: :artisans_tools, ability: :int},
  %{slug: "brewers-supplies", name: "Brewer's Supplies", category: :artisans_tools, ability: :int},
  %{slug: "calligraphers-supplies", name: "Calligrapher's Supplies", category: :artisans_tools, ability: :dex},
  %{slug: "carpenters-tools", name: "Carpenter's Tools", category: :artisans_tools, ability: :str},
  %{slug: "cartographers-tools", name: "Cartographer's Tools", category: :artisans_tools, ability: :wis},
  %{slug: "cobblers-tools", name: "Cobbler's Tools", category: :artisans_tools, ability: :dex},
  %{slug: "cooks-utensils", name: "Cook's Utensils", category: :artisans_tools, ability: :wis},
  %{slug: "glassblowers-tools", name: "Glassblower's Tools", category: :artisans_tools, ability: :int},
  %{slug: "jewelers-tools", name: "Jeweler's Tools", category: :artisans_tools, ability: :int},
  %{slug: "leatherworkers-tools", name: "Leatherworker's Tools", category: :artisans_tools, ability: :dex},
  %{slug: "masons-tools", name: "Mason's Tools", category: :artisans_tools, ability: :str},
  %{slug: "painters-supplies", name: "Painter's Supplies", category: :artisans_tools, ability: :wis},
  %{slug: "potters-tools", name: "Potter's Tools", category: :artisans_tools, ability: :int},
  %{slug: "smiths-tools", name: "Smith's Tools", category: :artisans_tools, ability: :str},
  %{slug: "tinkers-tools", name: "Tinker's Tools", category: :artisans_tools, ability: :dex},
  %{slug: "weavers-tools", name: "Weaver's Tools", category: :artisans_tools, ability: :dex},
  %{slug: "woodcarvers-tools", name: "Woodcarver's Tools", category: :artisans_tools, ability: :dex},

  # --- Other tools ---
  %{slug: "disguise-kit", name: "Disguise Kit", category: :tool, ability: :cha},
  %{slug: "forgery-kit", name: "Forgery Kit", category: :tool, ability: :dex},
  %{slug: "herbalism-kit", name: "Herbalism Kit", category: :tool, ability: :int},
  %{slug: "navigators-tools", name: "Navigator's Tools", category: :tool, ability: :wis},
  %{slug: "poisoners-kit", name: "Poisoner's Kit", category: :tool, ability: :int},
  %{slug: "thieves-tools", name: "Thieves' Tools", category: :tool, ability: :dex},

  # --- Gaming sets ---
  %{slug: "dice-set", name: "Dice Set", category: :gaming_set, ability: :wis},
  %{slug: "dragonchess-set", name: "Dragonchess Set", category: :gaming_set, ability: :wis},
  %{slug: "playing-card-set", name: "Playing Card Set", category: :gaming_set, ability: :wis},
  %{slug: "three-dragon-ante-set", name: "Three-Dragon Ante Set", category: :gaming_set, ability: :wis},

  # --- Musical instruments ---
  %{slug: "bagpipes", name: "Bagpipes", category: :musical_instrument, ability: :cha},
  %{slug: "drum", name: "Drum", category: :musical_instrument, ability: :cha},
  %{slug: "dulcimer", name: "Dulcimer", category: :musical_instrument, ability: :cha},
  %{slug: "flute", name: "Flute", category: :musical_instrument, ability: :cha},
  %{slug: "horn", name: "Horn", category: :musical_instrument, ability: :cha},
  %{slug: "lute", name: "Lute", category: :musical_instrument, ability: :cha},
  %{slug: "lyre", name: "Lyre", category: :musical_instrument, ability: :cha},
  %{slug: "pan-flute", name: "Pan Flute", category: :musical_instrument, ability: :cha},
  %{slug: "shawm", name: "Shawm", category: :musical_instrument, ability: :cha},
  %{slug: "viol", name: "Viol", category: :musical_instrument, ability: :cha},

  # --- Spellcasting focuses ---
  %{
    slug: "arcane-focus",
    name: "Arcane Focus",
    category: :focus,
    variants: ["Crystal", "Orb", "Rod", "Staff", "Wand"]
  },
  %{
    slug: "druidic-focus",
    name: "Druidic Focus",
    category: :focus,
    variants: ["Sprig of mistletoe", "Wooden staff", "Yew wand"]
  },
  %{
    slug: "holy-symbol",
    name: "Holy Symbol",
    category: :focus,
    variants: ["Amulet", "Emblem", "Reliquary"]
  },

  # --- Equipment packs ---
  %{
    slug: "burglars-pack",
    name: "Burglar's Pack",
    category: :pack,
    contents: [
      "backpack",
      "ball-bearings",
      "bell",
      {"candle", 10},
      "crowbar",
      "hooded-lantern",
      {"oil", 7},
      {"rations", 5},
      "rope",
      "tinderbox",
      "waterskin"
    ]
  },
  %{
    slug: "diplomats-pack",
    name: "Diplomat's Pack",
    category: :pack,
    contents: [
      "chest",
      "fine-clothes",
      "ink",
      {"ink-pen", 5},
      "lamp",
      {"map-or-scroll-case", 2},
      {"oil", 4},
      {"paper", 5},
      {"parchment", 5},
      "perfume",
      "tinderbox"
    ]
  },
  %{
    slug: "dungeoneers-pack",
    name: "Dungeoneer's Pack",
    category: :pack,
    contents: [
      "backpack",
      "caltrops",
      "crowbar",
      {"oil", 2},
      {"rations", 10},
      "rope",
      "tinderbox",
      {"torch", 10},
      "waterskin"
    ]
  },
  %{
    slug: "entertainers-pack",
    name: "Entertainer's Pack",
    category: :pack,
    contents: [
      "backpack",
      "bedroll",
      "bell",
      "bullseye-lantern",
      {"costume", 3},
      "mirror",
      {"oil", 8},
      {"rations", 9},
      "tinderbox",
      "waterskin"
    ]
  },
  %{
    slug: "explorers-pack",
    name: "Explorer's Pack",
    category: :pack,
    contents: [
      "backpack",
      "bedroll",
      {"oil", 2},
      {"rations", 10},
      "rope",
      "tinderbox",
      {"torch", 10},
      "waterskin"
    ]
  },
  %{
    slug: "priests-pack",
    name: "Priest's Pack",
    category: :pack,
    contents: [
      "backpack",
      "blanket",
      "holy-water",
      "lamp",
      {"rations", 7},
      "robe",
      "tinderbox"
    ]
  },
  %{
    slug: "scholars-pack",
    name: "Scholar's Pack",
    category: :pack,
    contents: [
      "backpack",
      "book",
      "ink",
      "ink-pen",
      "lamp",
      {"oil", 10},
      {"parchment", 10},
      "tinderbox"
    ]
  },

  # --- Adventuring gear ---
  %{slug: "arrows", name: "Arrows", category: :gear},
  %{slug: "backpack", name: "Backpack", category: :gear},
  %{slug: "ball-bearings", name: "Ball Bearings", category: :gear},
  %{slug: "bedroll", name: "Bedroll", category: :gear},
  %{slug: "bell", name: "Bell", category: :gear},
  %{slug: "blanket", name: "Blanket", category: :gear},
  %{slug: "book", name: "Book", category: :gear},
  %{slug: "bullseye-lantern", name: "Bullseye Lantern", category: :gear},
  %{slug: "caltrops", name: "Caltrops", category: :gear},
  %{slug: "candle", name: "Candle", category: :gear},
  %{slug: "chest", name: "Chest", category: :gear},
  %{slug: "costume", name: "Costume", category: :gear},
  %{slug: "crowbar", name: "Crowbar", category: :gear},
  %{slug: "fine-clothes", name: "Fine Clothes", category: :gear},
  %{slug: "healers-kit", name: "Healer's Kit", category: :gear},
  %{slug: "holy-water", name: "Holy Water", category: :gear},
  %{slug: "hooded-lantern", name: "Hooded Lantern", category: :gear},
  %{slug: "ink", name: "Ink", category: :gear},
  %{slug: "ink-pen", name: "Ink Pen", category: :gear},
  %{slug: "lamp", name: "Lamp", category: :gear},
  %{slug: "map-or-scroll-case", name: "Map or Scroll Case", category: :gear},
  %{slug: "mirror", name: "Mirror", category: :gear},
  %{slug: "oil", name: "Oil", category: :gear},
  %{slug: "paper", name: "Paper", category: :gear},
  %{slug: "parchment", name: "Parchment", category: :gear},
  %{slug: "perfume", name: "Perfume", category: :gear},
  %{slug: "pouch", name: "Pouch", category: :gear},
  %{slug: "quiver", name: "Quiver", category: :gear},
  %{slug: "rations", name: "Rations", category: :gear},
  %{slug: "robe", name: "Robe", category: :gear},
  %{slug: "rope", name: "Rope", category: :gear},
  # A Spellbook is granted by the Wizard's Spellcasting feature rather than the
  # gear table, but the Wizard's starting equipment names it.
  %{slug: "spellbook", name: "Spellbook", category: :gear},
  %{slug: "tinderbox", name: "Tinderbox", category: :gear},
  %{slug: "torch", name: "Torch", category: :gear},
  %{slug: "travelers-clothes", name: "Traveler's Clothes", category: :gear},
  %{slug: "waterskin", name: "Waterskin", category: :gear}
]
