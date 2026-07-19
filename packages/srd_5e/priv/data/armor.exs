# SRD 5.2 armor. See the package README for the SRD CC-BY attribution.
#
# Transcribed from the 2024 SRD armor table:
# https://5e24srd.com/equipment/armor.html
#
# `base_ac` is the base Armor Class; the Dexterity contribution follows from the
# category (light: full Dex; medium: Dex up to +2; heavy: none). For a shield,
# `base_ac` is the +2 bonus it grants. Cost and weight are not modeled yet.
[
  # --- Light ---
  %{slug: "padded", name: "Padded Armor", category: :light, base_ac: 11, stealth_disadvantage: true},
  %{slug: "leather", name: "Leather Armor", category: :light, base_ac: 11},
  %{slug: "studded-leather", name: "Studded Leather Armor", category: :light, base_ac: 12},

  # --- Medium ---
  %{slug: "hide", name: "Hide Armor", category: :medium, base_ac: 12},
  %{slug: "chain-shirt", name: "Chain Shirt", category: :medium, base_ac: 13},
  %{slug: "scale-mail", name: "Scale Mail", category: :medium, base_ac: 14, stealth_disadvantage: true},
  %{slug: "breastplate", name: "Breastplate", category: :medium, base_ac: 14},
  %{slug: "half-plate", name: "Half Plate Armor", category: :medium, base_ac: 15, stealth_disadvantage: true},

  # --- Heavy ---
  %{slug: "ring-mail", name: "Ring Mail", category: :heavy, base_ac: 14, stealth_disadvantage: true},
  %{slug: "chain-mail", name: "Chain Mail", category: :heavy, base_ac: 16, strength: 13, stealth_disadvantage: true},
  %{slug: "splint", name: "Splint Armor", category: :heavy, base_ac: 17, strength: 15, stealth_disadvantage: true},
  %{slug: "plate", name: "Plate Armor", category: :heavy, base_ac: 18, strength: 15, stealth_disadvantage: true},

  # --- Shield ---
  %{slug: "shield", name: "Shield", category: :shield, base_ac: 2}
]
