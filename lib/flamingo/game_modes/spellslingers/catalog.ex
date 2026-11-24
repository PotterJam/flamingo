defmodule Flamingo.GameModes.Spellslingers.Catalog do
  @moduledoc """
  The arsenal: every tool and explosive a miner carries, as in Worms. Everyone has the
  same kit, each with its ammo and the number of its thrower's turns before it unlocks.
  """

  @spell_defaults %{
    gravity: 1.0,
    wind: 1.0,
    speed: 1.0,
    radius: 0,
    damage: 0,
    knock: 0,
    # Quick spells leave the turn open, so the wizard can still walk and cast.
    quick: false,
    # Placed spells conjure where the player clicks; sky ones reach anywhere on the map.
    place: false,
    sky: false,
    # Aimless spells cast the moment they are picked and end the turn.
    aimless: false,
    # Grand spells open with a title card, a darkened sky and a letterbox.
    grand: false,
    # How far a beam reaches, in cells; nil reaches across the map.
    range: nil
  }

  # Each spell's id, look and numbers, in the order the panel and the number keys show
  # them. `sprite` is its frame in spells.webp, drawn in flight and as its icon.
  @spells [
            %{
              id: "firebolt",
              name: "Coal Bomb",
              blurb: "Your trusty lobbed lump of lit coal. Rides the wind, blasts a crater.",
              effect: :blast,
              color: "#f97316",
              sprite: 0,
              radius: 11,
              damage: 45,
              knock: 50
            },
            %{
              id: "fuserune",
              name: "Fuse Stone",
              blurb:
                "A stone packed with powder that bounces and rolls, then bursts on its fourth landing. Lob it into holes and round corners.",
              effect: :bounce,
              color: "#fb923c",
              sprite: 1,
              radius: 10,
              damage: 42,
              knock: 45,
              wind: 0.3
            },
            %{
              id: "embers",
              name: "Cinder Burst",
              blurb:
                "Bursts on impact and scatters five burning cinders that blast where they fall.",
              effect: :swarm,
              color: "#ef4444",
              sprite: 2,
              radius: 7,
              damage: 22,
              knock: 26
            },
            %{
              id: "thunderegg",
              name: "Thunder Geode",
              blurb:
                "Cracks open on impact and flings five geode shards that each go off like a Coal Bomb. Stand well back.",
              effect: :egg,
              color: "#3b82f6",
              sprite: 3,
              radius: 9,
              damage: 30,
              knock: 40,
              gravity: 1.1
            },
            %{
              id: "seeker",
              name: "Ghost Canary",
              blurb: "A lobbed canary that hunts the nearest enemy once it starts to fall.",
              effect: :seeker,
              color: "#22d3ee",
              sprite: 4,
              radius: 9,
              damage: 38,
              knock: 40
            },
            %{
              id: "hexhare",
              name: "Dynamite Hare",
              blurb:
                "Throw it and it hops on along the ground the way you threw it, then explodes on the first miner it meets.",
              effect: :hare,
              color: "#a855f7",
              sprite: 5,
              radius: 12,
              damage: 55,
              knock: 58,
              wind: 0.4
            },
            %{
              id: "lance",
              name: "Spark Spike",
              blurb:
                "A red-hot rivet fired dead straight. Ignores gravity and wind; hits the first thing.",
              effect: :blast,
              color: "#fde047",
              sprite: 11,
              radius: 4,
              damage: 26,
              knock: 26,
              gravity: 0.0,
              wind: 0.0,
              speed: 1.6
            },
            %{
              id: "hook",
              name: "Pick Hook",
              blurb:
                "Fling your pick on its chain. It bites the first miner along your aim and yanks them through the air to your feet: off their perch, out of cover, or into the sea.",
              effect: :hook,
              color: "#d97706",
              sprite: 12,
              damage: 12,
              gravity: 0.0,
              wind: 0.0,
              range: 32
            },
            %{
              id: "tunnel",
              name: "Rock Drill",
              blurb: "A steam drill that bores a tunnel straight through the land.",
              effect: :tunnel,
              color: "#f59e0b",
              sprite: 13,
              damage: 10,
              gravity: 0.0,
              wind: 0.0,
              range: 60
            },
            %{
              id: "blastrune",
              aimless: true,
              name: "Powder Keg",
              blurb:
                "Drops a powder keg at your feet. It goes off when your turn ends, so drop it next to someone and run.",
              effect: :blastrune,
              color: "#d946ef",
              sprite: 6,
              radius: 13,
              damage: 60,
              knock: 62
            },
            %{
              id: "meteors",
              place: true,
              sky: true,
              name: "Rockfall",
              blurb: "Point anywhere on the map: five boulders rake the ground there from above.",
              effect: :meteors,
              color: "#fb923c",
              sprite: 7,
              radius: 6,
              damage: 26,
              knock: 32
            },
            %{
              id: "slab",
              place: true,
              name: "Rail Slab",
              blurb: "Bolt a slab of stone in mid-air: a bridge, a roof, a perch.",
              effect: :slab,
              color: "#a8a29e",
              sprite: 14
            },
            %{
              id: "broom",
              quick: true,
              name: "Steam Pack",
              blurb:
                "Quick: strap it on and fly with WASD for 40 cells, then throw from the air. You drift down when the turn ends.",
              effect: :broom,
              color: "#a16207",
              sprite: 10
            },
            %{
              id: "blink",
              place: true,
              sky: true,
              name: "Burrow",
              blurb:
                "Dig down and pop up at any open spot on the map. You still get your retreat.",
              effect: :blink,
              color: "#a855f7",
              sprite: 15
            },
            %{
              id: "holyorb",
              grand: true,
              name: "Holy Lantern",
              blurb:
                "Big one. Bounces once, sings, then erupts in the biggest single blast there is.",
              effect: :holy,
              color: "#facc15",
              sprite: 9,
              radius: 17,
              damage: 80,
              knock: 80,
              gravity: 1.2,
              wind: 0.2
            },
            %{
              id: "anvil",
              grand: true,
              place: true,
              sky: true,
              name: "Anvil Drop",
              blurb:
                "Big one. A colossal anvil falls anywhere and smashes down through the land, blasting at every slam.",
              effect: :anvil,
              color: "#94a3b8",
              sprite: 8,
              radius: 8,
              damage: 30,
              knock: 34
            },
            %{
              id: "quake",
              grand: true,
              aimless: true,
              name: "Cave-In",
              blurb: "Big one. The whole island heaves: everyone else is hurt and thrown about.",
              effect: :quake,
              color: "#b45309",
              sprite: 17,
              damage: 18,
              knock: 30
            },
            %{
              id: "starfall",
              grand: true,
              aimless: true,
              name: "Slag Storm",
              blurb: "Big one. Molten slag rains down on every part of the map at once.",
              effect: :starfall,
              color: "#fde047",
              sprite: 16,
              radius: 6,
              damage: 22,
              knock: 26
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

            Map.put(spell, :input, input)
          end)

  @spell_index Map.new(@spells, &{&1.id, &1})

  # {spell, starting ammo, turns of its caster's before it unlocks}. Spell crates add ammo.
  @arsenal [
    {"firebolt", :infinite, 0},
    {"fuserune", :infinite, 0},
    {"embers", 2, 0},
    {"thunderegg", 1, 2},
    {"seeker", 2, 1},
    {"hexhare", 1, 1},
    {"lance", 3, 0},
    {"hook", 2, 0},
    {"tunnel", 2, 0},
    {"blastrune", 2, 0},
    {"meteors", 1, 2},
    {"slab", 3, 0},
    {"broom", 2, 0},
    {"blink", 1, 1},
    {"holyorb", 1, 3},
    {"anvil", 1, 4},
    {"quake", 1, 3},
    {"starfall", 1, 6}
  ]

  @arsenal_ids Enum.map(@arsenal, &elem(&1, 0))
  @starting_ammo for {id, ammo, _} <- @arsenal, ammo != :infinite, into: %{}, do: {id, ammo}
  @unlocks for {id, _, turns} <- @arsenal, turns > 0, into: %{}, do: {id, turns}

  @maps [
    {"isles", "Floating Isles"},
    {"flamingo", "Flamingo Isle"},
    {"castles", "Twin Keeps"},
    {"cavern", "Crystal Cavern"},
    {"archipelago", "Archipelago"}
  ]

  @map_ids Enum.map(@maps, &elem(&1, 0))

  def spells, do: @spells
  def maps, do: @maps
  def map_ids, do: @map_ids
  def arsenal_ids, do: @arsenal_ids
  def starting_ammo, do: @starting_ammo
  @doc "How many of its caster's turns must pass before a spell can be cast."
  def unlock(id), do: Map.get(@unlocks, id, 0)
  def grand?(id), do: match?(%{grand: true}, Map.get(@spell_index, id))
  def spell(id), do: Map.fetch!(@spell_index, id)

  def fetch_spell(id) do
    case Map.fetch(@spell_index, id) do
      {:ok, spell} -> {:ok, spell}
      :error -> {:error, :unknown_spell}
    end
  end
end
