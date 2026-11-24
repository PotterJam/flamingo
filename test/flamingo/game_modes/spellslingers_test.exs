defmodule Flamingo.GameModes.SpellslingersTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameModes.Spellslingers
  alias Flamingo.GameModes.Spellslingers.{Crates, Physics, Spells, Terrain}

  defp roster(order, offline \\ []) do
    %{
      players:
        Map.new(order, &{&1, %{id: &1, name: String.upcase(&1), connected: &1 not in offline}}),
      player_order: order,
      host_id: hd(order)
    }
  end

  defp context(roster, actor \\ "a"), do: %{roster: roster, actor_id: actor}

  defp started(order \\ ["a", "b"]) do
    r = roster(order)

    state =
      Enum.reduce(order, Spellslingers.new(), fn id, state ->
        {:ok, %{state: state}} = Spellslingers.admit_member(state, r.players[id], context(r))
        state
      end)

    {:ok, %{state: state}} =
      Spellslingers.start(state, %{seed: 42, turn_length: 30, arena_map: "isles"}, context(r))

    {begin(state, r), r}
  end

  # Every arena reports it has loaded, then the intro plays out.
  defp begin(state, r) do
    state =
      Enum.reduce(r.player_order, state, fn id, state ->
        case Spellslingers.command(state, id, :arena_loaded, context(r, id)) do
          {:ok, %{state: state}} -> state
          :ignored -> state
        end
      end)

    assert state.phase == :arena_intro
    {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_intro, context(r))
    assert state.phase == :arena_aim
    state
  end

  defp sign(n) when n < 0, do: -1
  defp sign(_n), do: 1

  # Aim straight at a target unit with a flat bolt, so the hit doesn't depend on wind.
  defp lance_at(state, from, to) do
    a = state.units[from]
    b = state.units[to]
    angle = :math.atan2(-(b.y - 1 - (a.y - 2)), b.x - a.x) * 180 / :math.pi()
    {:cast, "lance", angle, 100}
  end

  defp clear_line(state, from, to) do
    # Remove the rock between the two wizards, above the ground they stand on, so a
    # straight bolt can connect.
    a = state.units[from]
    b = state.units[to]
    {x0, x1} = Enum.min_max([a.x, b.x])
    top = min(a.y, b.y) - 6
    bottom = max(a.y, b.y)

    {width, height} = Spellslingers.dimensions()

    terrain =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if x > x0 + 1 and x < x1 - 1 and y >= top and y <= bottom,
          do: <<0>>,
          else: <<:binary.at(state.terrain, y * width + x)>>
      end

    %{state | terrain: terrain}
  end

  # Flat ground with its surface at row 80, and the wizards moved to the given columns.
  defp flat(state, columns) do
    {width, height} = Spellslingers.dimensions()

    terrain =
      for y <- 0..(height - 1),
          _x <- 0..(width - 1),
          into: <<>>,
          do: <<if(y > 80, do: 1, else: 0)>>

    units =
      Map.new(columns, fn {id, x} -> {id, %{state.units[id] | x: x, y: 80}} end)

    %{state | terrain: terrain, units: Map.merge(state.units, units)}
  end

  test "start requires the host and two online players" do
    r = roster(["a", "b"], ["b"])
    state = Spellslingers.new()
    assert {:error, :not_enough_players} = Spellslingers.start(state, %{seed: 42}, context(r))

    assert {:error, :not_host} =
             Spellslingers.start(state, %{seed: 42}, context(roster(["a", "b"]), "b"))
  end

  test "the first turn's clock waits for everyone's arena to load and the intro to play" do
    r = roster(["a", "b", "c"])

    state =
      Enum.reduce(r.player_order, Spellslingers.new(), fn id, state ->
        {:ok, %{state: state}} = Spellslingers.admit_member(state, r.players[id], context(r))
        state
      end)

    {:ok, %{state: state, timers: timers}} =
      Spellslingers.start(state, %{seed: 42, arena_map: "isles"}, context(r))

    assert state.phase == :arena_loading
    assert {:schedule_phase_timeout, :arena_loading, _} = List.last(timers)
    assert Enum.sort(Spellslingers.view(state, "a", r).loading) == ["a", "b", "c"]
    assert {:error, :not_your_turn} = Spellslingers.command(state, "a", :pass, context(r))

    {:ok, %{state: state}} = Spellslingers.command(state, "a", :arena_loaded, context(r, "a"))
    assert :ignored = Spellslingers.command(state, "a", :arena_loaded, context(r, "a"))
    {:ok, %{state: state}} = Spellslingers.command(state, "b", :arena_loaded, context(r, "b"))
    assert state.phase == :arena_loading
    assert Spellslingers.view(state, "a", r).loading == ["c"]

    # The last one dropping out is no reason to wait any longer.
    offline = roster(["a", "b", "c"], ["c"])

    {:ok, %{state: state, timers: timers}} =
      Spellslingers.connection_changed(state, "c", :offline, context(offline))

    assert state.phase == :arena_intro
    # A step per flamingo, then the tail.
    assert timers == [{:schedule_phase_timeout, :arena_intro, 900 * 3 + 700}]

    {:ok, %{state: state, timers: timers}} =
      Spellslingers.timeout(state, :arena_intro, context(offline))

    assert state.phase == :arena_aim
    assert {:schedule_phase_timeout, :arena_turn, 40_000} in timers
  end

  test "a duel starts anyway once the loading wait runs out" do
    r = roster(["a", "b"])

    state =
      Enum.reduce(r.player_order, Spellslingers.new(), fn id, state ->
        {:ok, %{state: state}} = Spellslingers.admit_member(state, r.players[id], context(r))
        state
      end)

    {:ok, %{state: state}} = Spellslingers.start(state, %{seed: 42}, context(r))
    {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_loading, context(r))
    assert state.phase == :arena_intro
  end

  test "wizards spawn standing on terrain, above the water, and only the current wizard may act" do
    {state, r} = started(["a", "b", "c"])

    for {_, unit} <- state.units do
      assert Terrain.solid?(state.terrain, unit.x, unit.y + 1)
      refute Terrain.solid?(state.terrain, unit.x, unit.y)
      assert unit.y < state.water_level
    end

    other = Enum.find(state.turn_order, &(&1 != state.current_id))

    assert {:error, :not_your_turn} =
             Spellslingers.command(state, other, {:walk, 1}, context(r, other))
  end

  test "a bolt into the ground beside the target hurts it, digs a crater, and passes the turn" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0}, first, second)
    a = state.units[first]
    b = state.units[second]
    # The ground two cells short of the target, on the caster's side.
    {gx, gy} = {b.x + 0.5 - 2.5 * sign(b.x - a.x), b.y + 1.5}
    angle = :math.atan2(-(gy - (a.y - 2)), gx - (a.x + 0.5)) * 180 / :math.pi()

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "lance", angle, 100}, context(r, first))

    assert cast.phase == :arena_resolve
    assert cast.units[second].hp < 150
    assert cast.damage_dealt[first] == 150 - cast.units[second].hp
    assert cast.terrain != state.terrain
    assert {:error, :not_your_turn} = Spellslingers.command(cast, first, :pass, context(r, first))

    # Once it has played out the caster gets a few seconds to run, but no second cast.
    {:ok, %{state: running, timers: timers}} =
      Spellslingers.timeout(cast, :arena_resolve, context(r))

    assert running.phase == :arena_aim and running.retreat and running.current_id == first
    assert Enum.any?(timers, &match?({:schedule_phase_timeout, :arena_retreat, _}, &1))

    assert {:error, :retreating} =
             Spellslingers.command(running, first, {:cast, "firebolt", 45, 50}, context(r, first))

    {:ok, %{state: next}} = Spellslingers.timeout(running, :arena_retreat, context(r))
    assert next.phase == :arena_aim
    refute next.retreat
    assert next.current_id == second
    # The lance came out of the caster's ammo, and nobody else's.
    assert Spellslingers.view(next, first, r).ammo["lance"] == 2
    assert Spellslingers.view(next, second, r).ammo["lance"] == 3
  end

  test "dev tuning changes the rules mid-game, clamped, until restored" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0}, first, second)
    ctx = context(r, first)

    lose = fn state ->
      {:ok, %{state: cast}} =
        Spellslingers.command(state, first, lance_at(state, first, second), ctx)

      150 - cast.units[second].hp
    end

    {:ok, %{state: tuned}} = Spellslingers.command(state, second, {:tune, "damage_pct", 50}, ctx)
    assert lose.(tuned) == round(lose.(state) / 2)

    # Out-of-range values clamp; whole-number rules stay whole.
    {:ok, %{state: tuned}} =
      Spellslingers.command(tuned, first, {:tune, "walk_budget", 999.4}, ctx)

    assert tuned.tuning.walk_budget == 200
    assert Spellslingers.view(tuned, first, r).tuned?

    assert {:error, :invalid_command} =
             Spellslingers.command(tuned, first, {:tune, "wizard_hp", 5}, ctx)

    {:ok, %{state: restored}} = Spellslingers.command(tuned, first, :reset_tuning, ctx)
    refute Spellslingers.view(restored, first, r).tuned?
    assert lose.(restored) == lose.(state)
  end

  test "every wizard carries the arsenal: ammo runs out, big spells unlock later, crates refill" do
    {state, r} = started()
    first = state.current_id
    ctx = context(r, first)
    view = Spellslingers.view(state, first, r)

    # Firebolt never runs out; the Thunder Egg waits two of its caster's turns.
    refute Map.has_key?(view.ammo, "firebolt")
    assert view.ammo["embers"] == 2
    assert view.locked["thunderegg"] == 2

    assert {:error, :spell_locked} =
             Spellslingers.command(state, first, {:cast, "thunderegg", 45, 50}, ctx)

    # The old spells are gone.
    assert {:error, :unknown_spell} =
             Spellslingers.command(state, first, {:cast, "ember", 45, 50}, ctx)

    unlocked = %{state | turns_taken: %{first => 2}}
    refute Map.has_key?(Spellslingers.view(unlocked, first, r).locked, "thunderegg")
    assert {:ok, _} = Spellslingers.command(unlocked, first, {:cast, "thunderegg", 45, 50}, ctx)

    empty = put_in(state.ammo[first]["embers"], 0)

    assert {:error, :no_ammo} =
             Spellslingers.command(empty, first, {:cast, "embers", 45, 50}, ctx)

    # Walking into a spell crate adds a charge of the spell it holds.
    me = empty.units[first]
    crate = %{id: "c1", kind: :crate, type: :mana, spell: "embers", x: me.x, y: me.y}
    refilled = Crates.collect_crates(%{empty | crates: [crate]})
    assert refilled.crates == []
    assert refilled.ammo[first]["embers"] == 1
  end

  test "a broomstick is quick: the wizard flies, can still cast, and flutters down after" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | sudden_after: 99})
    ctx = context(r, first)

    {:ok, %{state: state}} = Spellslingers.command(state, first, {:cast, "broom", 0, 0}, ctx)
    assert state.phase == :arena_aim and state.current_id == first
    assert state.walk_left == 80
    ground = state.units[first].y

    state =
      Enum.reduce(1..12, state, fn _, state ->
        {:ok, %{state: state}} = Spellslingers.command(state, first, {:rise, 1}, ctx)
        state
      end)

    assert state.units[first].y == ground - 12

    assert {:error, :quick_used} =
             Spellslingers.command(state, first, {:cast, "broom", 0, 0}, ctx)

    # Still in the air, the turn's one real spell goes off from up there.
    {:ok, %{state: cast}} = Spellslingers.command(state, first, {:cast, "firebolt", 90, 20}, ctx)
    assert cast.phase == :arena_resolve

    {:ok, %{state: theirs}} = Spellslingers.command(state, first, :pass, ctx)
    assert theirs.current_id == second
    assert theirs.units[first].y == ground
    # Coming down 12 cells hurts like any 12-cell fall, a point a cell past the safe 8.
    assert theirs.units[first].hp == 150 - (12 - 8)
  end

  test "a high jump clears a wall too steep to walk up, and a long jump goes further" do
    {state, r} = started()
    [first, _second] = state.turn_order
    {width, height} = Spellslingers.dimensions()

    # Flat ground with its surface at row 80 and a wall six cells high to the right.
    terrain =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if y > 80 or (x in 152..175 and y > 74), do: <<1>>, else: <<0>>
      end

    wizard = %{state.units[first] | x: 148, y: 80}
    others = Map.new(state.units, fn {id, u} -> {id, %{u | x: 20, y: 80}} end)
    state = %{state | terrain: terrain, units: Map.put(others, first, wizard), walk_left: 40}
    ctx = context(r, first)

    walked =
      Enum.reduce(1..3, state, fn _, state ->
        {:ok, %{state: state}} = Spellslingers.command(state, first, {:walk, 1}, ctx)
        state
      end)

    assert Spellslingers.command(walked, first, {:walk, 1}, ctx) == {:error, :blocked}

    # Right up against the wall, a high jump climbs its face and lands on top.
    {:ok, %{state: high}} = Spellslingers.command(walked, first, {:jump, :high, 1}, ctx)
    assert %{x: x, y: 74} = high.units[first]
    assert x > 151
    assert high.walk_left == 32
    assert high.units[first].hp == 150
    assert %{id: ^first, n: 1, path: [_, _ | _]} = high.last_jump

    {:ok, %{state: long}} = Spellslingers.command(state, first, {:jump, :long, -1}, ctx)
    {:ok, %{state: hop}} = Spellslingers.command(state, first, {:jump, :high, -1}, ctx)
    assert long.units[first].y == 80 and hop.units[first].y == 80
    assert 148 - long.units[first].x > 148 - hop.units[first].x + 6

    assert {:error, :no_steps_left} =
             Spellslingers.command(%{state | walk_left: 4}, first, {:jump, :long, 1}, ctx)

    # Boxed in by the map's edge and a low roof, a jump goes nowhere and costs nothing.
    boxed =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if y > 80 or (y == 76 and x < 6), do: <<1>>, else: <<0>>
      end

    cornered = %{state | terrain: boxed, units: Map.put(others, first, %{wizard | x: 0})}
    assert Spellslingers.command(cornered, first, {:jump, :high, -1}, ctx) == {:error, :blocked}
    assert Spellslingers.command(cornered, first, {:walk, -1}, ctx) == {:error, :blocked}

    # A jump off a high ledge hurts on landing, a point a cell past the safe 8, and the
    # chronicle says why.
    ledge =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if y > 80 or (x < 150 and y > 50), do: <<1>>, else: <<0>>
      end

    perched = %{state | terrain: ledge, units: Map.put(others, first, %{wizard | x: 147, y: 50})}
    {:ok, %{state: fell}} = Spellslingers.command(perched, first, {:jump, :long, 1}, ctx)
    lost = 150 - fell.units[first].hp
    assert fell.units[first].y == 80 and lost == 30 - 8
    assert Enum.any?(fell.events, &(&1 =~ "falls hard and loses #{lost} HP"))
  end

  test "an explosion knocks a nearby wizard away from the blast" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0}, first, second)
    before = state.units[second]

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, lance_at(state, first, second), context(r, first))

    moved = cast.units[second]
    direction = if before.x > state.units[first].x, do: 1, else: -1
    assert (moved.x - before.x) * direction > 0 or moved.dead
    assert Enum.any?(cast.last_cast.knocks, &(&1.id == second))
  end

  test "the pick hook yanks the first miner along the aim to land in front of the thrower" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = flat(calm(state), %{first => 60, second => 84})
    before = state.units[second].hp

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "hook", 0, 100}, context(r, first))

    pulled = cast.units[second]
    assert pulled.x >= 62 and pulled.x <= 66 and pulled.y == 80
    assert pulled.hp < before
  end

  test "the last wizard standing wins, and a drowned wizard is eliminated" do
    {state, r} = started(["a", "b", "c"])
    [first, second, third] = state.turn_order
    state = calm(%{state | sudden_after: 99})

    state = put_in(state.units[second].hp, 1)
    state = put_in(state.units[third].y, state.water_level)

    {:ok, result} = Spellslingers.command(state, first, :pass, context(r, first))
    assert result.state.units[third].dead
    refute result.state.units[second].dead
    assert result.state.current_id == second

    state = put_in(result.state.units[second].y, result.state.water_level).state
    {:ok, result} = Spellslingers.command(state, second, :pass, context(r, second))

    assert {:finished, %{winner_id: ^first, standings: standings}} = result.status
    assert Enum.map(standings, & &1.id) == [first, second, third]

    # The host can go again at once, on a fresh island, with the same settings.
    over = result.state
    assert {:error, :not_host} = Spellslingers.command(over, "b", :rematch, context(r, "b"))
    {:ok, %{state: again}} = Spellslingers.command(over, "a", :rematch, context(r, "a"))
    assert again.phase == :arena_loading
    assert again.map_id == "isles" and again.turn_length == 30
    assert Enum.all?(Map.values(again.units), &(&1.hp == 150 and not &1.dead))
  end

  test "leaving mid-duel forfeits, and the remaining wizard wins" do
    {state, r} = started()
    [first, second] = state.turn_order

    {:ok, result} =
      Spellslingers.remove_member(state, first, %{id: first}, context(roster([second])))

    assert {:finished, %{winner_id: ^second}} = result.status
    _ = r
  end

  test "a hex hare hops on along the ground and goes off on the first wizard it meets" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | turns_taken: %{first => 1}}) |> flat(%{first => 100, second => 132})

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "hexhare", 45, 30}, context(r, first))

    segments = cast.last_cast.segments
    assert length(segments) >= 2
    assert [%{radius: 12, hit: true}] = Enum.filter(segments, &(&1.radius > 0))
    assert cast.units[second].hp < 150
    assert cast.units[first].hp == 150
  end

  test "a blast rune goes off at the caster's feet when their turn ends" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | sudden_after: 99}) |> flat(%{first => 100, second => 103})

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "blastrune", 0, 0}, context(r, first))

    assert [%{owner: ^first}] = cast.runes
    assert cast.units[second].hp == 150

    # The caster runs clear during the retreat; the rune waits for the turn to end.
    {:ok, %{state: running}} = Spellslingers.timeout(cast, :arena_resolve, context(r))
    running = put_in(running.units[first].x, 40)

    {:ok, %{state: boom, timers: timers}} =
      Spellslingers.timeout(running, :arena_retreat, context(r))

    assert boom.phase == :arena_resolve and boom.runes == []
    assert Enum.any?(timers, &match?({:schedule_phase_timeout, :arena_runes, _}, &1))
    assert boom.units[second].hp < 110
    assert boom.units[first].hp == 150

    {:ok, %{state: next}} = Spellslingers.timeout(boom, :arena_runes, context(r))
    assert next.current_id == second
  end

  test "an egg laid in flight falls to the ground below, or into the sea" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | sudden_after: 99}) |> flat(%{first => 100, second => 140})
    flying = put_in(state.units[first], %{state.units[first] | y: 60, float: 1})

    {:ok, %{state: cast}} =
      Spellslingers.command(flying, first, {:cast, "blastrune", 0, 0}, context(r, first))

    # It rests on the ground (row 81 is the top of the rock), straight below.
    assert [%{owner: ^first, x: x, y: y}] = cast.runes
    assert_in_delta x, 100.5, 0.01
    assert_in_delta y, 81 - Physics.egg_radius(), 0.1

    assert [[_, landed] | _] =
             cast.last_cast.segments |> hd() |> Map.fetch!(:path) |> Enum.reverse()

    assert_in_delta landed, y, 0.01

    {width, height} = Spellslingers.dimensions()
    open_sea = %{flying | terrain: :binary.copy(<<0>>, width * height)}

    {:ok, %{state: lost}} =
      Spellslingers.command(open_sea, first, {:cast, "blastrune", 0, 0}, context(r, first))

    assert lost.runes == []
  end

  test "a Nest Egg rolls down a steep slope and stops on the flat below" do
    {state, r} = started()
    [first, second] = state.turn_order
    {width, height} = Spellslingers.dimensions()

    # A plateau at row 60 runs down a 45 degree slope to flat ground at row 80.
    surface = fn x -> 60 + clamp(x - 100, 0, 20) end

    terrain =
      for y <- 0..(height - 1),
          x <- 0..(width - 1),
          into: <<>>,
          do: <<if(y > surface.(x), do: 1, else: 0)>>

    units = %{
      first => %{state.units[first] | x: 104, y: 64},
      second => %{state.units[second] | x: 160, y: 80}
    }

    state = calm(%{state | terrain: terrain, units: Map.merge(state.units, units)})

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "blastrune", 0, 0}, context(r, first))

    assert [%{x: x, y: y, spin: spin}] = cast.runes
    assert x > 121
    assert_in_delta y, 81 - Physics.egg_radius(), 0.1
    assert spin > 0
  end

  defp clamp(n, low, high), do: n |> max(low) |> min(high)

  test "shots and blasts reach the flamingo as drawn, head to feet" do
    {state, _r} = started()
    [first, second] = state.turn_order
    state = flat(state, %{first => 100, second => 160})
    hit = fn x, up -> Physics.unit_hit(state, x, 81 - up, &(&1 == first)) end

    # The head stands about 8 cells above the feet; the legs are thin and the body round.
    assert hit.(100.5, 7.5) == first
    assert hit.(101.9, 4) == first
    assert hit.(100.5, 8.6) == nil
    assert hit.(101.9, 1) == nil

    # A small blast beside the head catches it.
    fx = Physics.explode(Spellslingers.Fx.new(state, nil), second, {104.5, 74}, 3, 20, 0)
    assert fx.state.units[first].hp < 150
  end

  test "the anvil smashes down through the land, blasting at every slam" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | turns_taken: %{first => 4}}) |> flat(%{first => 60, second => 150})

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:place, "anvil", 150.5, 20}, context(r, first))

    assert cast.last_cast.grand
    assert Enum.count(cast.last_cast.segments, &(&1.radius > 0)) >= 3
    refute Terrain.solid?(cast.terrain, 150, 92)
    assert cast.units[second].hp < 150 or cast.units[second].dead
  end

  test "sudden death drops everyone to one health, then the sea rises every turn" do
    {state, r} = started()
    sea = state.water_level
    state = calm(%{state | sudden_after: 0})

    state = next_turn(state, r)
    assert state.sudden_death
    assert Enum.all?(Map.values(state.units), &(&1.hp == 1))
    assert state.water_level == sea
    assert Enum.any?(state.events, &(&1 =~ "SUDDEN DEATH"))

    state = next_turn(state, r)
    assert state.water_level == sea - 3
  end

  test "views carry no spectator controls for late joiners" do
    {state, r} = started()
    {:ok, %{state: state}} = Spellslingers.admit_member(state, %{id: "z"}, context(r))
    view = Spellslingers.view(state, "z", r)
    assert view.participation == :spectator
    assert {:error, :spectator} = Spellslingers.command(state, "z", :pass, context(r, "z"))
  end

  test "AI wizards fill out a duel, take their own turns, and cap at five" do
    r = roster(["a"])

    {:ok, %{state: state}} =
      Spellslingers.admit_member(Spellslingers.new(), r.players["a"], context(r))

    assert {:error, :not_enough_players} = Spellslingers.start(state, %{seed: 42}, context(r))
    assert {:error, :invalid_bots} = Spellslingers.start(state, %{seed: 42, bots: 6}, context(r))

    {:ok, %{state: state}} =
      Spellslingers.start(state, %{seed: 42, bots: 2, arena_map: "isles"}, context(r))

    assert length(state.turn_order) == 3

    state = begin(state, r)
    state = if state.current_id == "a", do: pass(state, r), else: state
    bot = state.current_id
    assert "bot-" <> _ = bot

    # A bot thinks, walks a step per tick, shows everyone its aim, then casts.
    {state, aims} =
      Enum.reduce_while(1..60, {state, []}, fn _, {state, aims} ->
        {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_bot, context(r))
        aims = if state.bot_aim, do: [state.bot_aim | aims], else: aims
        if state.phase == :arena_resolve, do: {:halt, {state, aims}}, else: {:cont, {state, aims}}
      end)

    assert state.phase == :arena_resolve
    assert state.last_cast.caster_id == bot
    assert [%{spell: spell}] = aims
    assert state.last_cast.spell == spell
  end

  test "a shot through a wizard's hat counts as a hit" do
    {state, _r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0}, first, second)
    b = state.units[second]
    dir = if state.units[first].x < b.x, do: 1, else: -1
    lance = Enum.find(Spellslingers.spells(), &(&1.id == "lance"))

    # Level with the hat brim: above the body, but where the wizard is drawn.
    origin = {b.x + 0.5 - 12 * dir, b.y - 2.8}
    {_path, {kind, _}} = Physics.fly(state, origin, {60.0 * dir, 0.0}, lance, first)

    assert kind == :unit
  end

  test "placed spells conjure at the chosen point, within range only" do
    {state, r} = started()
    [first, _] = state.turn_order
    me = state.units[first]
    {x, y} = {me.x + 10, me.y - 12}

    assert {:error, :place_only} =
             Spellslingers.command(state, first, {:cast, "slab", 45, 100}, context(r, first))

    assert {:error, :out_of_range} =
             Spellslingers.command(
               state,
               first,
               {:place, "slab", me.x + 150, y},
               context(r, first)
             )

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:place, "slab", x, y}, context(r, first))

    assert Terrain.solid?(cast.terrain, x, y)
    refute Terrain.solid?(state.terrain, x, y)
  end

  test "an earthquake with no ground left still hurts every other wizard" do
    {state, r} = started()
    [first, second] = state.turn_order
    {width, height} = Spellslingers.dimensions()
    state = %{state | terrain: :binary.copy(<<0>>, width * height), turns_taken: %{first => 3}}

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "quake", 0, 0}, context(r, first))

    assert cast.units[second].hp < 150
    assert cast.damage_dealt[first] > 0
  end

  test "a winning shot stays a win even if the tide would drown the winner" do
    {state, r} = started()
    [first, second] = state.turn_order
    me = %{state.units[first] | y: state.water_level - 1}

    state = %{
      state
      | phase: :arena_resolve,
        current_id: first,
        sudden_death: true,
        units: %{
          state.units
          | first => me,
            second => %{state.units[second] | hp: 0, dead: true}
        }
    }

    {:ok, %{state: over}} = Spellslingers.timeout(state, :arena_resolve, context(r))

    assert over.phase == :game_ended
    assert over.final_result.winner_id == first
  end

  test "meteors from a surge land before the next wizard's clock starts" do
    {state, r} = started()
    state = %{state | turn_number: 10, sudden_after: 999}

    # Pass until wild magic rolls a meteor shower; the rng is seeded, so this is stable.
    {state, timers} =
      Enum.reduce_while(1..300, {state, []}, fn _, {state, _} ->
        {:ok, %{state: next, timers: timers}} =
          Spellslingers.command(state, state.current_id, :pass, context(r, state.current_id))

        if match?(%{caster_id: nil}, next.last_cast),
          do: {:halt, {next, timers}},
          else: {:cont, {next, timers}}
      end)

    assert state.phase == :arena_resolve
    assert Enum.any?(timers, &match?({:schedule_phase_timeout, :arena_surge, _}, &1))

    {:ok, %{state: next}} = Spellslingers.timeout(state, :arena_surge, context(r))
    assert next.phase in [:arena_aim, :game_ended]
  end

  test "a knock carries a wizard on past the map's edge until it lands in the sea" do
    {state, _r} = started()
    [_first, second] = state.turn_order
    {width, height} = Spellslingers.dimensions()
    sea = state.water_level

    # Ground right up to the edge; nothing past it.
    terrain =
      for y <- 0..(height - 1),
          _x <- 0..(width - 1),
          into: <<>>,
          do: <<if(y > 80, do: 1, else: 0)>>

    unit = %{state.units[second] | x: width - 3, y: 80}
    state = %{state | terrain: terrain, units: %{second => unit}}

    {knocked, [%{path: path}]} = Physics.apply_knocks(state, %{second => {40, -30}})

    assert %{y: ^sea, x: x} = knocked.units[second]
    assert x >= width + 10
    # It was still in the air, not yet in the water, when it crossed the edge.
    assert Enum.any?(path, fn {px, py} -> px >= width and py < sea - 10 end)
  end

  test "a wizard knocked into the sea beside a cliff is out, not lifted onto the cliff" do
    {state, _r} = started()
    [_first, second] = state.turn_order
    {width, height} = Spellslingers.dimensions()
    x = width - 1
    sea = state.water_level

    # Knockback leaves a unit that left the map at the waterline; here that spot
    # is inside a cliff, which is what used to lift it back up with full health.
    terrain =
      for y <- 0..(height - 1), cx <- 0..(width - 1), into: <<>> do
        if cx >= x - 2 and y >= sea - 8,
          do: <<1>>,
          else: <<:binary.at(state.terrain, y * width + cx)>>
      end

    unit = %{state.units[second] | x: x, y: sea}
    state = %{state | terrain: terrain, units: %{state.units | second => unit}}

    after_knock = Spells.run(state, nil, "surge", nil, & &1)

    assert after_knock.units[second].dead
  end

  test "each hit is timed to the moment the meteor that strikes the wizard lands" do
    {state, _r} = started()
    [first, second] = state.turn_order
    state = %{state | wind: 0}
    a = state.units[first]
    b = state.units[second]

    # The later meteor falls on the first wizard, so hits follow landings, not unit order.
    cast =
      Spells.run(state, nil, "surge", nil, fn fx ->
        fx
        |> Spells.meteor(b.x + 0.5, 0, "surge")
        |> Spells.meteor(a.x + 0.5, 40, "surge")
      end).last_cast

    [late, early] = cast.segments |> Enum.sort_by(& &1.start, :desc)
    landing = fn segment -> segment.start + length(segment.path) - 1 end

    assert [%{id: ^second, at: at_b}] = Enum.filter(cast.hits, &(&1.id == second))
    assert [%{id: ^first, at: at_a}] = Enum.filter(cast.hits, &(&1.id == first))
    assert at_b == landing.(early)
    assert at_a == landing.(late)
    assert at_a > at_b
    assert cast.flight_steps > at_a
  end

  test "a wizard's health only goes down as hits land, even when a later hit lands first" do
    {state, _r} = started()
    [first, _second] = state.turn_order
    state = %{state | wind: 0}
    a = state.units[first]

    # The second meteor is worked out after the first but lands well before it.
    cast =
      Spells.run(state, nil, "surge", nil, fn fx ->
        fx
        |> Spells.meteor(a.x + 0.5, 40, "surge")
        |> Spells.meteor(a.x + 0.5, 0, "surge")
      end)

    hits = Enum.filter(cast.last_cast.hits, &(&1.id == first))
    assert [early, late] = hits
    assert early.at < late.at
    assert a.hp > early.hp and early.hp > late.hp
    assert late.hp == cast.units[first].hp
  end

  defp pass(state, r) do
    {:ok, %{state: state}} = Spellslingers.command(state, "a", :pass, context(r, "a"))
    state
  end

  # Wild magic and crates off, so turns run the same every time.
  defp calm(state),
    do: %{state | wind: 0, tuning: %{state.tuning | surge_chance: 0, crate_chance: 0}}

  defp next_turn(state, r) do
    {:ok, %{state: state}} =
      Spellslingers.command(state, state.current_id, :pass, context(r, state.current_id))

    state
  end

  test "a seeker wisp thrown straight up comes down on the enemy, not on its caster" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(%{state | turns_taken: %{first => 1}})

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "seeker", 90, 75}, context(r, first))

    [x, _] = cast.last_cast.segments |> hd() |> Map.fetch!(:path) |> List.last()
    assert abs(x - state.units[second].x) < abs(x - state.units[first].x)
  end

  test "a fuse rune bounces off the ground before it bursts" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = calm(state)
    toward = if state.units[second].x > state.units[first].x, do: -40, else: 220

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "fuserune", toward, 60}, context(r, first))

    [first_hop | _] = segments = cast.last_cast.segments
    assert length(segments) > 1
    assert first_hop.hit and first_hop.radius == 0
    # Each hop starts where the last one stopped.
    for [a, b] <- Enum.chunk_every(segments, 2, 1, :discard),
        do: assert(b.start == a.start + length(a.path) - 1)
  end

  describe "history" do
    test "the last wizard standing wins and wizards who left are unranked" do
      {state, r} = started(["a", "b", "c"])
      state = %{state | damage_dealt: %{"a" => 30, "b" => 12, "c" => 0}}
      {:ok, %{state: state}} = Spellslingers.remove_member(state, "c", %{id: "c"}, context(r))

      {:ok, %{status: {:finished, result}}} =
        Spellslingers.remove_member(state, "b", %{id: "b"}, context(r))

      history = Spellslingers.history(result)
      assert history.completed?
      assert history.drawings == []

      assert Enum.sort(Enum.map(history.players, &{&1.seat_id, &1.score, &1.placement})) ==
               [{"a", 30, 1}, {"b", 12, nil}, {"c", 0, nil}]
    end

    test "AI wizards are left out, a duel needs two humans and nobody surviving has no winner" do
      result = %{
        winner_id: nil,
        map_id: "isles",
        bots: ["bot-1"],
        forfeited: [],
        standings: [
          %{id: "bot-1", place: 1, damage: 50},
          %{id: "a", place: 2, damage: 40},
          %{id: "b", place: 3, damage: 10}
        ]
      }

      history = Spellslingers.history(result)
      assert history.completed?
      assert Enum.map(history.players, &{&1.seat_id, &1.placement}) == [{"a", 3}, {"b", 4}]

      refute Spellslingers.history(%{result | standings: Enum.take(result.standings, 2)}).completed?
    end
  end
end
