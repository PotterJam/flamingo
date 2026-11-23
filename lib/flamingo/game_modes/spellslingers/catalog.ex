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
    place: false,
    # Grand spells: one per book, charging for the caster's first turns and castable once
    # per duel. Sky spells strike anywhere from above, so they have no placing range.
    grand: false,
    sky: false,
    aimless: false
  }

  # A grand spell is ready on its caster's fifth turn.
  @grand_charge 4

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
    "swap" => "#f0abfc",
    "napalm" => "#ea580c",
    "skipstone" => "#a8a29e",
    "seeker" => "#38bdf8",
    "cataclysm" => "#fb923c",
    "volcano" => "#b91c1c",
    "thunderhead" => "#fde047",
    "tide" => "#2563eb",
    "dragon" => "#7c3aed",
    "frostbolt" => "#67e8f9",
    "icefloe" => "#bae6fd",
    "blizzard" => "#e0f2fe",
    "nova" => "#7dd3fc",
    "iceage" => "#22d3ee",
    "bonespear" => "#e7e5e4",
    "decay" => "#84cc16",
    "raisedead" => "#65a30d",
    "drain" => "#e11d48",
    "lich" => "#a3e635",
    "clockbomb" => "#f59e0b",
    "turret" => "#64748b",
    "tower" => "#94a3b8",
    "magnet" => "#ef4444",
    "doomsday" => "#dc2626"
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
              id: "napalm",
              name: "Napalm Flask",
              blurb:
                "A lobbed flask that splashes fire on the ground. It burns anyone standing in it for a few turns.",
              icon: :flask_conical,
              effect: :napalm,
              radius: 3,
              damage: 10,
              knock: 10,
              cooldown: 2
            },
            %{
              id: "skipstone",
              name: "Skipping Stone",
              blurb:
                "Bounces off the ground three times, then bursts. Lob it into a hole or round a corner.",
              icon: :disc,
              effect: :bounce,
              radius: 6,
              damage: 26,
              knock: 34,
              wind: 0.5,
              cooldown: 2
            },
            %{
              id: "seeker",
              name: "Seeker Arrow",
              blurb: "A lobbed arrow that turns toward the nearest enemy once it starts to fall.",
              icon: :locate_fixed,
              effect: :seeker,
              radius: 3,
              damage: 20,
              knock: 16,
              cooldown: 2
            },
            %{
              id: "cataclysm",
              grand: true,
              place: true,
              sky: true,
              name: "Cataclysm",
              blurb:
                "Grand spell. Tear open the sky anywhere: a burning meteor gouges a vast crater.",
              icon: :orbit,
              effect: :cataclysm,
              radius: 16,
              damage: 60,
              knock: 70
            },
            %{
              id: "volcano",
              grand: true,
              place: true,
              sky: true,
              name: "Volcano",
              blurb:
                "Grand spell. A volcano bursts from the ground and hurls lava bombs for three rounds.",
              icon: :mountain_snow,
              effect: :volcano,
              radius: 5,
              damage: 14,
              knock: 22
            },
            %{
              id: "thunderhead",
              grand: true,
              place: true,
              sky: true,
              name: "Thunderhead",
              blurb:
                "Grand spell. A storm parks over a strip of the map and strikes it for three rounds. Lightning seeks the tallest target.",
              icon: :cloud_rain_wind,
              effect: :thunderhead,
              radius: 3,
              damage: 18,
              knock: 16
            },
            %{
              id: "tide",
              grand: true,
              aimless: true,
              name: "Rising Tide",
              blurb:
                "Grand spell. The sea rises now and on each of your next three turns. High ground wins.",
              icon: :waves,
              effect: :tide
            },
            %{
              id: "dragon",
              grand: true,
              place: true,
              name: "Summon Dragon",
              blurb:
                "Grand spell. A flying dragon that breathes fire at the nearest enemy every turn.",
              icon: :bird,
              effect: :summon,
              minion: :dragon
            },
            %{
              id: "frostbolt",
              name: "Frost Shard",
              blurb:
                "A lobbed shard of ice. Anyone caught in it is frozen solid and loses their next turn.",
              icon: :snowflake,
              effect: :freeze_bolt,
              radius: 4,
              damage: 16,
              knock: 10,
              cooldown: 3
            },
            %{
              id: "icefloe",
              place: true,
              name: "Ice Floe",
              blurb: "Freezes the sea's surface into a sheet of ice you can walk across.",
              icon: :diamond,
              effect: :icefloe,
              cooldown: 2
            },
            %{
              id: "blizzard",
              place: true,
              sky: true,
              name: "Blizzard",
              blurb:
                "Snow hammers a stretch of the map at the start of each of your next three turns.",
              icon: :cloud_snow,
              effect: :blizzard,
              damage: 9,
              cooldown: 5
            },
            %{
              id: "nova",
              aimless: true,
              name: "Frost Nova",
              blurb: "Casts on picking: everything close to you is chilled and frozen.",
              icon: :thermometer_snowflake,
              effect: :nova,
              radius: 12,
              damage: 10,
              cooldown: 4
            },
            %{
              id: "iceage",
              grand: true,
              aimless: true,
              name: "Ice Age",
              blurb:
                "Grand spell. Every enemy and their minions freeze solid and lose a turn, so you act twice.",
              icon: :mountain_snow,
              effect: :ice_age,
              damage: 20
            },
            %{
              id: "bonespear",
              name: "Bone Spear",
              blurb: "A straight, fast spear of bone. Ignores gravity and wind.",
              icon: :bone,
              effect: :blast,
              radius: 2,
              damage: 24,
              knock: 10,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.5,
              cooldown: 2
            },
            %{
              id: "decay",
              name: "Decay Bolt",
              blurb:
                "A lobbed blob of rot. Anyone splashed keeps losing health at the start of their next three turns.",
              icon: :droplets,
              effect: :decay,
              radius: 5,
              damage: 10,
              knock: 14,
              cooldown: 2
            },
            %{
              id: "raisedead",
              place: true,
              name: "Raise Dead",
              blurb: "A shambling zombie claws out of the ground. Slow, tough, bites hard.",
              icon: :hand,
              effect: :summon,
              minion: :zombie,
              cooldown: 3
            },
            %{
              id: "drain",
              aimless: true,
              name: "Life Drain",
              blurb:
                "Casts on picking: rips life from every enemy near you and heals you with it.",
              icon: :heart_crack,
              effect: :drain,
              radius: 20,
              damage: 10,
              cooldown: 3
            },
            %{
              id: "lich",
              grand: true,
              aimless: true,
              name: "Lichdom",
              blurb:
                "Grand spell. Become a Lich: up to 150 health, and you drain every enemy at the start of your next five turns.",
              icon: :skull,
              effect: :lich,
              damage: 8
            },
            %{
              id: "clockbomb",
              name: "Clockwork Bomb",
              blurb:
                "Lob a ticking bomb. It goes off at the start of your next turn, unless they run.",
              icon: :alarm_clock,
              effect: :clockbomb,
              radius: 8,
              damage: 36,
              knock: 44,
              cooldown: 3
            },
            %{
              id: "turret",
              place: true,
              name: "Build Turret",
              blurb:
                "A bolted-down turret that shoots the nearest enemy at the start of your turns.",
              icon: :crosshair,
              effect: :summon,
              minion: :turret,
              cooldown: 4
            },
            %{
              id: "tower",
              aimless: true,
              name: "Arcane Tower",
              blurb: "Casts on picking: a stone tower lifts you high and wards you.",
              icon: :tower_control,
              effect: :tower,
              cooldown: 4
            },
            %{
              id: "magnet",
              name: "Magnet Pulse",
              blurb: "A straight pulse that yanks everything near where it lands toward you.",
              icon: :magnet,
              effect: :magnet,
              radius: 10,
              damage: 4,
              knock: 50,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.2,
              cooldown: 2
            },
            %{
              id: "doomsday",
              grand: true,
              place: true,
              sky: true,
              name: "Doomsday Clock",
              blurb:
                "Grand spell. Drop a colossal clockwork bomb anywhere. Two turns later it levels everything around it.",
              icon: :clock_alert,
              effect: :doomsday,
              radius: 20,
              damage: 65,
              knock: 70
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
                spell.quick or spell.aimless -> "instant"
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
      blurb: "Cluster hexes, meteors, napalm, an imp, and the grand Cataclysm.",
      color: "#f97316",
      spells: ~w(cluster inferno firerain imp napalm cataclysm)
    },
    %{
      id: "geo",
      icon: :mountain,
      name: "Geomancy",
      blurb: "Boulders, skipping stones, walls, a golem, quakes, and the grand Volcano.",
      color: "#a16207",
      spells: ~w(boulder rampart golem quake skipstone volcano)
    },
    %{
      id: "storm",
      icon: :cloud_lightning,
      name: "Tempest",
      blurb: "Lances, seeker arrows, chain strikes, gales, a wisp, and the grand Thunderhead.",
      color: "#0ea5e9",
      spells: ~w(lance gust chain wisp seeker thunderhead)
    },
    %{
      id: "wild",
      icon: :leaf,
      name: "Wildcraft",
      blurb: "Thornlings, tunnels, healing, the Chaos Orb, and the grand Rising Tide.",
      color: "#16a34a",
      spells: ~w(thornling bloom burrow chaos tide)
    },
    %{
      id: "sky",
      icon: :feather,
      name: "Skyward",
      blurb: "Levitate, ledges, updrafts, warp-swaps, and a grand fire-breathing dragon.",
      color: "#8b5cf6",
      spells: ~w(levitate ledge updraft swap dragon)
    },
    %{
      id: "frost",
      icon: :snowflake,
      name: "Frost",
      blurb: "Freezing shards, ice floes, blizzards, a frost nova, and the grand Ice Age.",
      color: "#06b6d4",
      spells: ~w(frostbolt icefloe blizzard nova iceage)
    },
    %{
      id: "dark",
      icon: :skull,
      name: "Underdark",
      blurb: "Bone spears, decay, the walking dead, life drain, and the grand Lichdom.",
      color: "#9f1239",
      spells: ~w(bonespear decay raisedead drain lich)
    },
    %{
      id: "cogs",
      icon: :cog,
      name: "Cogs",
      blurb: "Clockwork bombs, turrets, towers, magnets, and the grand Doomsday Clock.",
      color: "#475569",
      spells: ~w(clockbomb turret tower magnet doomsday)
    }
  ]

  @book_ids Enum.map(@books, & &1.id)

  @minions %{
    thornling: %{name: "thornling", hp: 30, bite: 14, hop: 12, reach: 5},
    imp: %{name: "imp", hp: 20, bite: 10, hop: 20, reach: 7},
    golem: %{name: "golem", hp: 60, bite: 20, hop: 5, reach: 5},
    wisp: %{name: "wisp", hp: 15, bite: 8, hop: 26, reach: 9},
    # The dragon flies and breathes fire instead of biting.
    dragon: %{name: "dragon", hp: 120, bite: 0, hop: 12, reach: 0},
    zombie: %{name: "zombie", hp: 40, bite: 16, hop: 7, reach: 5},
    # The turret never moves; it shoots at the start of its owner's turn instead (see Zones).
    turret: %{name: "turret", hp: 50, bite: 0, hop: 0, reach: 0}
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
  def grand_charge, do: @grand_charge
  def grand?(id), do: match?(%{grand: true}, Map.get(@spell_index, id))
  def spell(id), do: Map.fetch!(@spell_index, id)
  def minion(kind), do: Map.fetch!(@minions, kind)

  def fetch_spell(id) do
    case Map.fetch(@spell_index, id) do
      {:ok, spell} -> {:ok, spell}
      :error -> {:error, :unknown_spell}
    end
  end
end
