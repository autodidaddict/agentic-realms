defmodule AgenticRealms.GameData do
  @moduledoc """
  Static mock data for the Agentic Realms UI prototype.
  All game data is hardcoded here for the GUI design language feature.
  """

  @spec rooms() :: map()
  def rooms do
    %{
      tavern: %{
        id: :tavern,
        name: "The Gilded Kraken",
        coord: "3,2",
        desc:
          "The common room is low-ceilinged and smoky, lit by tallow candles that gutter whenever the door swings open. A minstrel's lute leans forgotten against the hearth. The floor is sticky with spilled mead.",
        exits: [
          %{dir: "north", to: "Back Rooms"},
          %{dir: "east", to: "Market Square"},
          %{dir: "down", to: "Cellar"}
        ],
        entities: [
          %{name: "Odra the innkeep", type: "npc"},
          %{name: "a weathered lute", type: "item"},
          %{name: "a brass tankard", type: "item"},
          %{name: "Thornwick", type: "player-other"},
          %{name: "Sable", type: "player-other"}
        ]
      }
    }
  end

  @spec starting_log() :: [map()]
  def starting_log do
    tavern = rooms().tavern

    [
      %{kind: :room, room: tavern},
      %{
        kind: :narrate,
        text:
          "You have been travelling three days without rest. The warmth of the tavern settles into your bones like an old debt being paid."
      },
      %{
        kind: :system,
        text: "Sable waves you over. You notice a sealed letter on her table."
      },
      %{kind: :cmd, text: "look at letter"},
      %{
        kind: :narrate,
        text:
          "A heavy parchment, folded twice and sealed with a wax sigil you do not recognize — a coiled serpent swallowing its own crown."
      },
      %{
        kind: :said,
        who: "Sable",
        text: "Don't open it here. The walls have ears, and the innkeep's one of them."
      },
      %{
        kind: :whisper,
        text: "a voice, near your ear but unseen — 'three more will die before the moon turns'"
      }
    ]
  end

  @spec inventory() :: [map()]
  def inventory do
    [
      %{name: "warhammer of dawn", qty: 1, equipped: true},
      %{name: "scale mail", qty: 1, equipped: true},
      %{name: "holy symbol, silver", qty: 1, equipped: true},
      %{name: "healing draught", qty: 3, equipped: false},
      %{name: "wax-sealed letter", qty: 1, equipped: false},
      %{name: "gold crown", qty: 47, equipped: false},
      %{name: "dried rations", qty: 5, equipped: false}
    ]
  end

  # Feature 013 — quests/0 and quest_details/0 removed. Quest log is now
  # backed by `AgenticRealms.World.Quests.active_for/1` and
  # `history_for/1`, computed from `quest_instances` + current inventory.

  @spec presence() :: [map()]
  def presence do
    [
      %{name: "Sable", status: "active", npc: false},
      %{name: "Thornwick", status: "active", npc: false},
      %{name: "Odra", status: "active", npc: true},
      %{name: "Vosk", status: "idle", npc: false}
    ]
  end

  # Feature 012 removed `map_nodes/0` and `map_edges/0` — the mini-map
  # is now driven by `AgenticRealms.World.MapView` over real world state.

  @spec starter_prompts() :: map()
  def starter_prompts do
    %{
      item:
        "A brass astrolabe, tarnished, etched with stars you do not recognize. Heavy — fixed to a reading table in the library. Turning the rings causes the candles in the room to dim.",
      npc:
        "Malveth, a ghostly librarian who drifts between the shelves of the Whispering Stacks. His robes trail cold mist, his eyes are hollowed coin, and his voice whispers as if through dry leaves. Incorporeal, level 9, wise and intelligent but physically frail. Wields cold channeling magic. On death he always drops the key to the Archive Vestibule, and may drop ash-black ink, spectral dust, a rare book, or (very rarely) his tattered robe.",
      room:
        "A library three floors underground, lit only by candles that burn with a cold blue flame. The shelves are so tall their tops are lost in darkness. Taking a book without trading a secret makes the archivist hostile.",
      quest:
        "A quest to recover three stolen letters from the Gilded Kraken tavern. Given by Malveth the archivist. Reward: ash-black ink, xp, archive faction.",
      spell:
        "A cleric spell that briefly reveals the true name of one creature you can see. 8 mana."
    }
  end

  @spec default_tweaks() :: map()
  def default_tweaks do
    %{
      theme: "phosphor",
      density: "comfortable",
      player_layout: "classic",
      wizard_preview: "card",
      show_hud: true
    }
  end

  @spec wizard_examples() :: map()
  def wizard_examples do
    %{
      room: %{
        kind: "Room",
        icon: "⌂",
        slug: "rooms/whispering-stacks",
        title: "The Whispering Stacks",
        fields: [
          %{k: "biome", kind: "tags", items: ["arcane", "interior"]},
          %{k: "light", v: "dim · cold-blue", kind: "tag"},
          %{
            k: "exits",
            kind: "exits",
            exits: [%{dir: "up", to: "Archive Vestibule"}]
          },
          %{
            k: "entities",
            kind: "entities",
            entities: [
              %{name: "Malveth", type: "NPC"},
              %{name: "brass astrolabe", type: "ITEM, movable"},
              %{name: "Book of Lesser Graces", type: "ITEM, takeable"}
            ]
          }
        ],
        triggers: [
          %{
            id: "trg_book_taken",
            intent: "Take",
            note: "If a player pockets a book without trading a secret...",
            conditions: [
              %{op: "not_has_flag", subject: "player", value: "traded_secret_today"},
              %{op: "gte", subject: "player.stealth", value: "0"}
            ],
            actions: [
              %{kind: "spawn_entity", target: "npc_malveth", attrs: "hostile · incorporeal"},
              %{
                kind: "emit_text",
                scope: "room",
                text:
                  "Cold mist pours from the shelves. Malveth materializes, eyes like hollowed coin."
              },
              %{kind: "set_disposition", target: "npc_malveth", value: "hostile"}
            ]
          }
        ],
        ingame:
          ~s(<div class="room-head"><span class="room-name">The Whispering Stacks</span><span class="room-coord">deep library · unseen</span></div><div class="room-body">The shelves are so tall their tops are lost in darkness. Candles burn with a <em>cold blue flame</em>, and when you speak, the books rustle — in rough agreement or disapproval. A brass astrolabe sits on a reading table.</div><div class="exits"><button class="exit-chip"><span class="arrow">↑</span> up · Archive Vestibule</button></div><div class="entities"><span class="entity npc">Malveth</span>, a ghostly librarian, drifts between the stacks. You see <span class="entity item">a brass astrolabe</span> and <span class="entity item">the Book of Lesser Graces</span>.</div>)
      },
      item: %{
        kind: "Item",
        icon: "❖",
        slug: "items/brass-astrolabe",
        title: "Brass Astrolabe",
        fields: [
          %{k: "name", v: "astrolabe", kind: "prose"},
          %{k: "pickable", v: "false · fixed to reading table", kind: "tag"},
          %{k: "short desc", v: "a brass astrolabe", kind: "prose"},
          %{
            k: "long desc",
            v:
              "Brass, tarnished, etched with stars you do not recognize. It hums faintly beneath your fingers. The rings move stiffly, as if remembering centuries of sky.",
            kind: "prose"
          },
          %{
            k: "adjectives",
            kind: "adjectives",
            note: "used for target disambiguation",
            items: ["brass", "tarnished", "heavy", "astronomical", "old", "rings", "astrolabe"]
          }
        ],
        triggers: [
          %{
            id: "trg_astrolabe_use",
            intent: "Use",
            note: "When a player moves or turns the astrolabe, the room dims.",
            conditions: [
              %{op: "equals", subject: "room.light", value: "candle-lit"},
              %{op: "has_tag", subject: "item_brass_astrolabe", value: "unlocked"}
            ],
            actions: [
              %{
                kind: "modify_prop",
                target: "rm_whispering_stacks",
                prop: "light",
                value: "near-dark · cold-blue"
              },
              %{
                kind: "emit_text",
                scope: "room",
                text: "The candles flinch, and the library dims as if dusk had just arrived."
              }
            ]
          }
        ],
        ingame:
          ~s(<div class="log-entry narrate">Brass, tarnished, etched with stars you do not recognize. It hums faintly beneath your fingers.</div>)
      },
      npc: %{
        kind: "NPC",
        icon: "☗",
        slug: "npcs/malveth-the-archivist",
        title: "Malveth, the Archivist",
        fields: [
          %{k: "name", v: "Malveth", kind: "prose"},
          %{k: "short desc", v: "a ghostly librarian in trailing robes", kind: "prose"},
          %{
            k: "long desc",
            v:
              "Malveth is an incorporeal archivist tethered to the Whispering Stacks, his robes trailing cold mist as he drifts between the shelves. His eyes are hollowed coin, his voice a whisper as through dry leaves. He guards the library's forbidden volumes and will trade a book only for a truth.",
            kind: "prose"
          },
          %{
            k: "adjectives",
            kind: "adjectives",
            note: "used for target disambiguation",
            items: [
              "ghostly",
              "spectral",
              "archivist",
              "librarian",
              "robed",
              "old",
              "malveth",
              "incorporeal"
            ]
          },
          %{k: "level", v: "9", kind: "num"},
          %{
            k: "hp / mp",
            kind: "stats",
            stats: [
              %{k: "Health", v: "180"},
              %{k: "Mana", v: "220"}
            ]
          },
          %{
            k: "stats",
            kind: "stats",
            stats: [
              %{k: "Strength", v: "6", sub: "-2"},
              %{k: "Dexterity", v: "14", sub: "+2"},
              %{k: "Wisdom", v: "19", sub: "+4"},
              %{k: "Charisma", v: "16", sub: "+3"},
              %{k: "Constitution", v: "10", sub: "+0"},
              %{k: "Intellect", v: "20", sub: "+5"}
            ]
          },
          %{
            k: "loot",
            kind: "loot",
            items: [
              %{name: "Key to Archive Vestibule", chance: 100},
              %{name: "Ash-black Ink", chance: 80},
              %{name: "Book of Lesser Graces", chance: 25},
              %{name: "Spectral Dust", chance: 60},
              %{name: "Tattered Archivist's Robe", chance: 10}
            ]
          }
        ],
        triggers: [
          %{
            id: "trg_whisper_secret",
            intent: "Whisper",
            note: "A player who speaks a true secret earns Malveth's favor.",
            conditions: [
              %{op: "equals", subject: "npc_malveth.disposition", value: "aloof"},
              %{op: "contains", subject: "input.utterance", value: "secret"}
            ],
            actions: [
              %{kind: "require_input", target: "player", prompt: "What truth do you offer?"},
              %{kind: "grant_item", target: "player", value: "Book of Lesser Graces"},
              %{
                kind: "emit_text",
                scope: "player",
                text: "Malveth inclines his head. 'A fair trade.' The book is warm to the touch."
              }
            ]
          }
        ],
        ingame:
          ~s(<div class="log-entry"><span class="entity npc">Malveth</span> solidifies from the candlelight, his robes trailing cold mist. "A seeker," he whispers, "or a thief? Speak a secret, and the book is yours."</div>)
      },
      quest: %{
        kind: "Quest",
        icon: "✦",
        slug: "quests/the-ink-that-remembers",
        title: "The Ink That Remembers",
        fields: [
          %{k: "giver", v: "Malveth (archivist)", kind: "prose"},
          %{
            k: "goal",
            v: "Recover three stolen letters from the Gilded Kraken tavern",
            kind: "prose"
          },
          %{
            k: "steps",
            kind: "steps",
            steps: [
              %{
                id: "step_find_letter_1",
                desc: "Find the first letter hidden in the tavern cellar."
              },
              %{id: "step_find_letter_2", desc: "Find the second letter carried by the barmaid."},
              %{
                id: "step_find_letter_3",
                desc: "Find the third letter locked in the captain's chest."
              },
              %{
                id: "step_return_malveth",
                desc: "Return the three letters to Malveth, unopened."
              },
              %{
                id: "step_choose_fate",
                desc: "Decide: reveal the letters' contents, or burn them."
              }
            ]
          },
          %{
            k: "rewards",
            kind: "rewards",
            rewards: [
              %{kind: "item", value: "item_ash_black_ink", label: "Ash-black Ink"},
              %{kind: "xp", value: "400"},
              %{kind: "faction", value: "+2 Archive"}
            ]
          }
        ],
        triggers: [],
        ingame: nil
      },
      spell: %{
        kind: "Spell",
        icon: "✧",
        slug: "spells/true-name",
        title: "True Name",
        fields: [
          %{k: "school", v: "divination", kind: "tag"},
          %{k: "cost", v: "8 mana", kind: "tag"},
          %{
            k: "effect",
            v: "Briefly reveals the true name of one creature you can see.",
            kind: "prose"
          },
          %{k: "range", v: "line of sight", kind: "tag"},
          %{k: "duration", v: "instant", kind: "tag"}
        ],
        triggers: [],
        ingame:
          ~s(<div class="log-entry narrate">You whisper the old words. For a heartbeat, the creature's true name blazes in your mind — ancient, unpronounceable, and binding.</div>)
      }
    }
  end

  @doc """
  Returns the streaming response text for the "read letter" command.
  """
  @spec streaming_response() :: String.t()
  def streaming_response do
    "You break the wax seal. Beneath the parchment, in ink that smells faintly of iron, the letter begins: 'If you are reading this, I am already in the Archivist's debt, and you are the only one I trust to settle it.'"
  end

  @doc """
  Maps presence names to their detailed role info for the modal.
  """
  @spec presence_roles() :: map()
  def presence_roles do
    %{
      "Sable" => %{role: "Informant · tier 3", kind: "other"},
      "Thornwick" => %{role: "Ranger · party", kind: "other"},
      "Odra" => %{role: "Innkeep · friendly", kind: "npc"},
      "Vosk" => %{role: "Mercenary · neutral", kind: "other"}
    }
  end

  @doc """
  Maps trigger action kind atoms to human-readable labels.
  """
  @spec action_labels() :: map()
  def action_labels do
    %{
      "emit_text" => "Emit text",
      "modify_prop" => "Modify prop",
      "spawn_entity" => "Spawn entity",
      "set_disposition" => "Set disposition",
      "grant_item" => "Grant item",
      "require_input" => "Require input",
      "move_entity" => "Move entity"
    }
  end

  @doc """
  Maps condition operator codes to display labels.
  """
  @spec condition_ops() :: map()
  def condition_ops do
    %{
      "equals" => "equals",
      "not_equals" => "≠",
      "has_tag" => "has tag",
      "not_has_flag" => "lacks flag",
      "gte" => "≥",
      "lte" => "≤",
      "contains" => "contains"
    }
  end

  @doc """
  Returns the list of available trigger intents for the intent dropdown.
  """
  @spec trigger_intents() :: [String.t()]
  def trigger_intents do
    ["Friendly Touch", "Look", "Use", "Take", "Attack", "Speak", "Whisper", "Move"]
  end
end
