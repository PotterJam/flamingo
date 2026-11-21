defmodule Flamingo.GameModes.Spellslingers.Catalog do
  @moduledoc false

  @spell_defaults %{
    gravity: 1.0,
    wind: 1.0,
    speed: 1.0,
    radius: 0,
    damage: 0,
    knock: 0,
    cooldown: 0,
    minion: nil,
    quick: false,
    place: false
  }

  # The colour clients draw each spell's flight, aim line and effects in.
  @colors %{
    "ember" => "#f97316",
    "blink" => "#c084fc",
    "cluster" => "#ef4444",
    "inferno" => "#facc15",
    "firerain" => "#fb923c",
    "imp" => "#dc2626",
    "boulder" => "#78716c",
    "rampart" => "#a16207",
    "golem" => "#57534e",
    "quake" => "#92400e",
    "lance" => "#fde047",
    "gust" => "#e0f2fe",
    "chain" => "#93c5fd",
    "wisp" => "#a5f3fc",
    "thornling" => "#22c55e",
    "bloom" => "#f472b6",
    "burrow" => "#d97706",
    "chaos" => "#d946ef",
    "ward" => "#60a5fa",
    "levitate" => "#c4b5fd",
    "ledge" => "#a8a29e",
    "updraft" => "#7dd3fc",
    "swap" => "#f0abfc"
  }

  @spells [
            %{
              id: "ember",
              name: "Ember Bolt",
              blurb: "A lobbed fireball that blasts a crater.",
              icon: :flame,
              effect: :blast,
              radius: 5,
              damage: 30,
              knock: 32
            },
            %{
              id: "blink",
              name: "Blink",
              blurb: "Throw your spark and appear wherever it lands.",
              icon: :sparkles,
              effect: :blink,
              cooldown: 3
            },
            %{
              id: "cluster",
              name: "Cluster Hex",
              blurb: "Bursts into four fire bomblets on impact.",
              icon: :bomb,
              effect: :cluster,
              radius: 4,
              damage: 14,
              knock: 22,
              cooldown: 2
            },
            %{
              id: "inferno",
              name: "Inferno Orb",
              blurb: "Slow, heavy and enormous. Clears a hillside.",
              icon: :sun,
              effect: :blast,
              radius: 10,
              damage: 42,
              knock: 52,
              gravity: 1.15,
              speed: 0.9,
              cooldown: 4
            },
            %{
              id: "firerain",
              name: "Meteor Rain",
              blurb: "Mark a spot with a flare; five meteors rain down around it.",
              icon: :cloud_hail,
              effect: :rain,
              radius: 4,
              damage: 14,
              knock: 20,
              cooldown: 3
            },
            %{
              id: "imp",
              place: true,
              name: "Summon Imp",
              blurb: "A fast, fragile imp that leaps at enemies.",
              icon: :flame_kindling,
              effect: :summon,
              minion: :imp,
              cooldown: 3
            },
            %{
              id: "boulder",
              name: "Boulder Toss",
              blurb: "Heavy rock. Big crater, shrugs off the wind.",
              icon: :mountain,
              effect: :blast,
              radius: 9,
              damage: 26,
              knock: 45,
              gravity: 1.3,
              wind: 0.3,
              cooldown: 2
            },
            %{
              id: "rampart",
              place: true,
              name: "Raise Rampart",
              blurb: "Raises a wall of earth where you point. Build cover or bridges.",
              icon: :brick_wall,
              effect: :raise,
              radius: 7,
              cooldown: 1
            },
            %{
              id: "golem",
              place: true,
              name: "Summon Golem",
              blurb: "A slow stone golem. Tough, blocks shots, hits hard.",
              icon: :hammer,
              effect: :summon,
              minion: :golem,
              cooldown: 4
            },
            %{
              id: "quake",
              name: "Earthquake",
              blurb:
                "The ground heaves: every other unit is hurt and tossed, and the land cracks.",
              icon: :activity,
              effect: :quake,
              damage: 12,
              cooldown: 5
            },
            %{
              id: "lance",
              name: "Storm Lance",
              blurb: "A straight, fast bolt of lightning. Ignores gravity and wind.",
              icon: :zap,
              effect: :blast,
              radius: 3,
              damage: 22,
              knock: 18,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.4,
              cooldown: 1
            },
            %{
              id: "gust",
              name: "Gale Blast",
              blurb: "A straight blast of wind. Barely hurts, flings everything nearby.",
              icon: :wind,
              effect: :gust,
              radius: 10,
              damage: 4,
              knock: 78,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.2,
              cooldown: 2
            },
            %{
              id: "chain",
              name: "Chain Lightning",
              blurb: "Strikes, then arcs to the two nearest other units.",
              icon: :cloud_lightning,
              effect: :chain,
              radius: 3,
              damage: 16,
              knock: 12,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.4,
              cooldown: 3
            },
            %{
              id: "wisp",
              place: true,
              name: "Summon Wisp",
              blurb: "A darting wisp with a long reach and little health.",
              icon: :ghost,
              effect: :summon,
              minion: :wisp,
              cooldown: 2
            },
            %{
              id: "thornling",
              place: true,
              name: "Summon Thornling",
              blurb: "A thorny sprite that hops toward enemies and bites.",
              icon: :sprout,
              effect: :summon,
              minion: :thornling,
              cooldown: 3
            },
            %{
              id: "bloom",
              place: true,
              name: "Healing Bloom",
              blurb: "Heals you and your minions near where you point.",
              icon: :flower,
              effect: :heal,
              radius: 14,
              damage: 25,
              cooldown: 3
            },
            %{
              id: "burrow",
              name: "Burrow Ray",
              blurb: "A beam that bores a tunnel straight through the land.",
              icon: :pickaxe,
              effect: :burrow,
              radius: 3,
              damage: 8,
              gravity: 0.0,
              wind: 0.0,
              cooldown: 2
            },
            %{
              id: "ward",
              name: "Arcane Ward",
              blurb:
                "Quick: a shield that soaks 40 damage and most knockback until your next turn. You can still cast after it.",
              icon: :shield,
              effect: :ward,
              quick: true,
              cooldown: 3
            },
            %{
              id: "levitate",
              name: "Levitate",
              blurb:
                "Quick: float this turn and next. Walk over gaps, rise and sink with W / S, no fall damage.",
              icon: :feather,
              effect: :levitate,
              quick: true,
              cooldown: 4
            },
            %{
              id: "ledge",
              place: true,
              name: "Conjure Ledge",
              blurb: "Builds a stone ledge in mid-air where you point. Bridges, perches, roofs.",
              icon: :layers,
              effect: :ledge,
              cooldown: 1
            },
            %{
              id: "updraft",
              name: "Updraft",
              blurb: "Hurls everything near the impact high into the sky.",
              icon: :arrow_big_up,
              effect: :updraft,
              radius: 9,
              knock: 60,
              cooldown: 2
            },
            %{
              id: "swap",
              name: "Warp Swap",
              blurb: "Hit a wizard or minion and you trade places with it.",
              icon: :arrow_left_right,
              effect: :swap,
              cooldown: 3
            },
            %{
              id: "chaos",
              name: "Chaos Orb",
              blurb: "Nobody knows. Not even you.",
              icon: :dices,
              effect: :chaos,
              cooldown: 3
            }
          ]
          |> Enum.map(&Map.merge(@spell_defaults, &1))
          |> Enum.map(fn spell ->
            # How a player aims it: hold to charge a lob, click to fire a straight
            # beam, click to place it, or cast at once on picking it.
            input =
              cond do
                spell.quick -> "instant"
                spell.place -> "place"
                spell.gravity == 0 -> "beam"
                true -> "charge"
              end

            Map.merge(spell, %{input: input, color: Map.fetch!(@colors, spell.id)})
          end)

  @spell_index Map.new(@spells, &{&1.id, &1})

  @core ~w(ember blink ward)

  @books [
    %{
      id: "pyro",
      icon: :flame,
      name: "Pyromancy",
      blurb: "Cluster hexes, raining meteors, a huge inferno and a cackling imp.",
      color: "#f97316",
      spells: ~w(cluster inferno firerain imp)
    },
    %{
      id: "geo",
      icon: :mountain,
      name: "Geomancy",
      blurb: "Hurl boulders, raise walls, summon a golem and shake the world.",
      color: "#a16207",
      spells: ~w(boulder rampart golem quake)
    },
    %{
      id: "storm",
      icon: :cloud_lightning,
      name: "Tempest",
      blurb: "Lightning lances, chain strikes, flinging gales and a darting wisp.",
      color: "#0ea5e9",
      spells: ~w(lance gust chain wisp)
    },
    %{
      id: "wild",
      icon: :leaf,
      name: "Wildcraft",
      blurb: "Thornlings, tunnels, healing, and the Chaos Orb.",
      color: "#16a34a",
      spells: ~w(thornling bloom burrow chaos)
    },
    %{
      id: "sky",
      icon: :feather,
      name: "Skyward",
      blurb: "Levitate over gaps, conjure ledges, fling foes skyward and warp-swap.",
      color: "#8b5cf6",
      spells: ~w(levitate ledge updraft swap)
    }
  ]

  @book_ids Enum.map(@books, & &1.id)

  @minions %{
    thornling: %{name: "thornling", hp: 30, bite: 14, hop: 12, reach: 5},
    imp: %{name: "imp", hp: 20, bite: 10, hop: 20, reach: 7},
    golem: %{name: "golem", hp: 60, bite: 20, hop: 5, reach: 5},
    wisp: %{name: "wisp", hp: 15, bite: 8, hop: 26, reach: 9}
  }

  @maps [
    {"isles", "Floating Isles"},
    {"flamingo", "Flamingo Isle"},
    {"castles", "Twin Keeps"},
    {"cavern", "Crystal Cavern"},
    {"archipelago", "Archipelago"}
  ]

  @map_ids Enum.map(@maps, &elem(&1, 0))

  def spells, do: @spells
  def books, do: @books
  def maps, do: @maps
  def map_ids, do: @map_ids
  def book_ids, do: @book_ids
  def core, do: @core
  def spell(id), do: Map.fetch!(@spell_index, id)
  def minion(kind), do: Map.fetch!(@minions, kind)

  def fetch_spell(id) do
    case Map.fetch(@spell_index, id) do
      {:ok, spell} -> {:ok, spell}
      :error -> {:error, :unknown_spell}
    end
  end
end
