defmodule Flamingo.GameModes.Spellslingers.Catalog do
  @moduledoc """
  The arsenal: every trick a flamingo has up its wing, as in Worms. Everyone has the
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
              name: "Mud Pie",
              blurb:
                "Your trusty lobbed pie of sticky nest mud. Rides the wind, blasts a crater.",
              effect: :blast,
              color: "#c2410c",
              sprite: 0,
              radius: 11,
              damage: 45,
              knock: 50
            },
            %{
              id: "fuserune",
              name: "Beach Ball",
              blurb:
                "A striped beach ball stuffed with fizz that bounces and rolls, then bursts on its fourth landing. Bounce it into holes and round corners.",
              effect: :bounce,
              color: "#06b6d4",
              sprite: 1,
              radius: 10,
              damage: 42,
              knock: 45,
              wind: 0.3
            },
            %{
              id: "embers",
              name: "Pomegranate",
              blurb:
                "Bursts on impact and scatters five fizzing seeds that blast where they fall.",
              effect: :swarm,
              color: "#e11d48",
              sprite: 2,
              radius: 7,
              damage: 22,
              knock: 26
            },
            %{
              id: "thunderegg",
              name: "Pineapple",
              blurb:
                "Splits open on impact and flings five chunks that each go off like a Mud Pie. Stand well back.",
              effect: :egg,
              color: "#eab308",
              sprite: 3,
              radius: 9,
              damage: 30,
              knock: 40,
              gravity: 1.1
            },
            %{
              id: "seeker",
              name: "Brine Fly",
              blurb: "A buzzing brine fly that hunts the nearest enemy once it starts to fall.",
              effect: :seeker,
              color: "#14b8a6",
              sprite: 4,
              radius: 9,
              damage: 38,
              knock: 40
            },
            %{
              id: "hexhare",
              name: "Wind-up Crab",
              blurb:
                "Throw it and it scuttles on along the ground the way you threw it, then explodes on the first flamingo it meets.",
              effect: :hare,
              color: "#dc2626",
              sprite: 5,
              radius: 12,
              damage: 55,
              knock: 58,
              wind: 0.4
            },
            %{
              id: "lance",
              name: "Quill Dart",
              blurb:
                "A stiff pink flight feather flicked dead straight. Ignores gravity and wind; hits the first thing.",
              effect: :blast,
              color: "#ec4899",
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
              name: "Shrimp on a String",
              blurb:
                "Dangle a juicy shrimp on a line. The first flamingo along your aim can't resist: it lunges after it through the air to your feet, off its perch, out of cover, or into the sea.",
              effect: :hook,
              color: "#fb7185",
              sprite: 12,
              damage: 12,
              gravity: 0.0,
              wind: 0.0,
              range: 32
            },
            %{
              id: "tunnel",
              name: "Beak Dredge",
              blurb: "Plunge your beak in and dredge a tunnel straight through the land.",
              effect: :tunnel,
              color: "#a16207",
              sprite: 13,
              damage: 10,
              gravity: 0.0,
              wind: 0.0,
              range: 60
            },
            %{
              id: "blastrune",
              aimless: true,
              name: "Nest Egg",
              blurb:
                "Lays a speckled egg at your feet. It hatches with a bang when your turn ends, so lay it next to someone and run.",
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
              name: "Coconut Drop",
              blurb: "Point anywhere on the map: five coconuts rain down on the ground there.",
              effect: :meteors,
              color: "#92400e",
              sprite: 7,
              radius: 6,
              damage: 26,
              knock: 32
            },
            %{
              id: "slab",
              place: true,
              name: "Mud Shelf",
              blurb: "Slap a shelf of nest mud into the air: a bridge, a roof, a perch.",
              effect: :slab,
              color: "#a8a29e",
              sprite: 14
            },
            %{
              id: "broom",
              quick: true,
              name: "Take Flight",
              blurb:
                "Quick: spread your wings and fly with WASD for 40 cells, then throw from the air. You flutter down when the turn ends.",
              effect: :broom,
              color: "#f472b6",
              sprite: 10
            },
            %{
              id: "blink",
              place: true,
              sky: true,
              name: "Migrate",
              blurb:
                "Fly off and touch down at any open spot on the map. You still get your retreat.",
              effect: :blink,
              color: "#f472b6",
              sprite: 15
            },
            %{
              id: "holyorb",
              grand: true,
              name: "Disco Ball",
              blurb:
                "Big one. Bounces once, spins and sings, then erupts in the biggest single blast there is.",
              effect: :holy,
              color: "#e879f9",
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
              name: "Lawn Flamingo",
              blurb:
                "Big one. A colossal plastic lawn flamingo plunges from the sky stakes first and smashes down through the land, blasting at every slam.",
              effect: :anvil,
              color: "#f472b6",
              sprite: 8,
              radius: 8,
              damage: 30,
              knock: 34
            },
            %{
              id: "quake",
              grand: true,
              aimless: true,
              name: "Flock Stomp",
              blurb:
                "Big one. The whole flock stamps in time: the island heaves, and everyone else is hurt and thrown about.",
              effect: :quake,
              color: "#be185d",
              sprite: 17,
              damage: 18,
              knock: 30
            },
            %{
              id: "starfall",
              grand: true,
              aimless: true,
              name: "Shrimp Storm",
              blurb: "Big one. Red-hot shrimp rain down on every part of the map at once.",
              effect: :starfall,
              color: "#f97316",
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
