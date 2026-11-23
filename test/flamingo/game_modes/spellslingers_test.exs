defmodule Flamingo.GameModes.SpellslingersTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameModes.Spellslingers
  alias Flamingo.GameModes.Spellslingers.{Physics, Spells, Terrain}

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

    assert state.phase == :arena_books
    {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_books, context(r))
    # Everyone gets the storm book so tests can cast Storm Lance.
    state = %{state | books: Map.new(order, &{&1, ["storm", "sky"]})}
    {state, r}
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

  test "start requires the host and two online players" do
    r = roster(["a", "b"], ["b"])
    state = Spellslingers.new()
    assert {:error, :not_enough_players} = Spellslingers.start(state, %{seed: 42}, context(r))

    assert {:error, :not_host} =
             Spellslingers.start(state, %{seed: 42}, context(roster(["a", "b"]), "b"))
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
    assert cast.units[second].hp < 100
    assert cast.damage_dealt[first] == 100 - cast.units[second].hp
    assert cast.terrain != state.terrain
    assert {:error, :not_your_turn} = Spellslingers.command(cast, first, :pass, context(r, first))

    {:ok, %{state: next}} = Spellslingers.timeout(cast, :arena_resolve, context(r))
    assert next.phase == :arena_aim
    assert next.current_id == second
    # Storm Lance has a one-turn cooldown that survives the turn it was cast on.
    assert next.cooldowns[first]["lance"] == 1

    {:ok, %{state: back}} = Spellslingers.command(next, second, :pass, context(r, second))
    assert back.current_id == first

    assert {:error, :spell_cooling_down} =
             Spellslingers.command(back, first, {:cast, "lance", 0, 50}, context(r, first))

    {:ok, %{state: back}} = Spellslingers.command(back, first, :pass, context(r, first))
    {:ok, %{state: back}} = Spellslingers.command(back, second, :pass, context(r, second))
    assert back.cooldowns[first]["lance"] == 0
  end

  test "dev tuning changes the rules mid-game, clamped, until restored" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0}, first, second)
    ctx = context(r, first)

    lose = fn state ->
      {:ok, %{state: cast}} =
        Spellslingers.command(state, first, lance_at(state, first, second), ctx)

      100 - cast.units[second].hp
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

  test "a cooling-down spell or one outside your spellbook is refused" do
    {state, r} = started()
    first = state.current_id
    state = put_in(state.cooldowns[first]["gust"], 2)

    assert {:error, :spell_cooling_down} =
             Spellslingers.command(state, first, {:cast, "gust", 45, 50}, context(r, first))

    assert {:error, :unknown_spell} =
             Spellslingers.command(state, first, {:cast, "inferno", 45, 50}, context(r, first))
  end

  test "the duel begins once every online wizard has pressed Ready on two spellbooks" do
    r = roster(["a", "b"])

    state =
      Enum.reduce(["a", "b"], Spellslingers.new(), fn id, state ->
        {:ok, %{state: state}} = Spellslingers.admit_member(state, r.players[id], context(r))
        state
      end)

    {:ok, %{state: state}} =
      Spellslingers.start(state, %{seed: 42, arena_map: "castles"}, context(r))

    run = fn state, steps ->
      Enum.reduce(steps, state, fn {id, command}, state ->
        {:ok, %{state: state}} = Spellslingers.command(state, id, command, context(r, id))
        state
      end)
    end

    # Two books alone don't start it, and Ready needs two books.
    state =
      run.(state, [{"a", {:choose_book, "pyro"}}, {"a", {:choose_book, "geo"}}])

    assert {:error, :choose_two_books} =
             Spellslingers.command(state, "b", :toggle_ready, context(r, "b"))

    # Changing a pick after Ready takes the Ready back.
    state =
      run.(state, [
        {"a", :toggle_ready},
        {"a", {:choose_book, "geo"}},
        {"a", {:choose_book, "sky"}},
        {"b", {:choose_book, "geo"}},
        {"b", {:choose_book, "storm"}},
        {"b", :toggle_ready}
      ])

    assert state.phase == :arena_books
    assert state.ready == ["b"]

    state = run.(state, [{"a", :toggle_ready}])

    assert state.phase == :arena_aim
    assert "inferno" in Spellslingers.spellbook(state, "a")
    assert "levitate" in Spellslingers.spellbook(state, "a")
    assert "chain" in Spellslingers.spellbook(state, "b")
    refute "inferno" in Spellslingers.spellbook(state, "b")
  end

  test "a ward is a quick spell: the turn continues, and it soaks damage and knockback" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0, turn_number: 0}, first, second)

    {:ok, %{state: warded}} =
      Spellslingers.command(state, first, {:cast, "ward", 0, 0}, context(r, first))

    assert warded.phase == :arena_aim and warded.current_id == first

    assert {:error, :quick_used} =
             Spellslingers.command(warded, first, {:cast, "levitate", 0, 0}, context(r, first))

    {:ok, %{state: next}} = Spellslingers.command(warded, first, :pass, context(r, first))
    before = next.units[first]

    {:ok, %{state: hit}} =
      Spellslingers.command(next, second, lance_at(next, second, first), context(r, second))

    # Storm Lance deals at most 22, all of it soaked by the 40-point ward.
    assert hit.units[first].hp == 100
    assert hit.units[first].ward < 40
    assert abs(hit.units[first].x - before.x) <= 2
  end

  test "levitating wizards hover, can rise, and land gently when it wears off" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = %{state | turn_number: 0, rise_after: 99}

    {:ok, %{state: state}} =
      Spellslingers.command(state, first, {:cast, "levitate", 0, 0}, context(r, first))

    ground = state.units[first].y

    state =
      Enum.reduce(1..12, state, fn _, state ->
        {:ok, %{state: state}} =
          Spellslingers.command(state, first, {:rise, 1}, context(r, first))

        state
      end)

    assert state.units[first].y == ground - 12

    {:ok, %{state: state}} = Spellslingers.command(state, first, :pass, context(r, first))
    {:ok, %{state: state}} = Spellslingers.command(state, second, :pass, context(r, second))
    assert state.units[first].y == ground - 12
    {:ok, %{state: state}} = Spellslingers.command(state, first, :pass, context(r, first))
    assert state.units[first].y == ground
    assert state.units[first].hp == 100
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
    assert high.units[first].hp == 100
    assert %{id: ^first, n: 1, path: [_, _ | _]} = high.last_jump

    {:ok, %{state: long}} = Spellslingers.command(state, first, {:jump, :long, -1}, ctx)
    {:ok, %{state: hop}} = Spellslingers.command(state, first, {:jump, :high, -1}, ctx)
    assert long.units[first].y == 80 and hop.units[first].y == 80
    assert 148 - long.units[first].x > 148 - hop.units[first].x + 6

    assert {:error, :no_steps_left} =
             Spellslingers.command(%{state | walk_left: 4}, first, {:jump, :long, 1}, ctx)
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

  test "the last wizard standing wins, and a drowned wizard is eliminated" do
    {state, r} = started(["a", "b", "c"])
    [first, second, third] = state.turn_order
    # No random wild-magic surges or crates interfering with this scenario.
    state = %{state | turn_number: 0, rise_after: 99}

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
  end

  test "leaving mid-duel forfeits, and the remaining wizard wins" do
    {state, r} = started()
    [first, second] = state.turn_order

    {:ok, result} =
      Spellslingers.remove_member(state, first, %{id: first}, context(roster([second])))

    assert {:finished, %{winner_id: ^second}} = result.status
    _ = r
  end

  test "summoned thornlings hop toward an enemy and bite at the end of their owner's turn" do
    {state, r} = started()
    [first, second] = state.turn_order
    target = state.units[second]

    thornling = %{
      id: "m1",
      kind: :thornling,
      owner: first,
      x: target.x,
      y: target.y,
      hp: 30,
      max_hp: 30,
      dead: false
    }

    state = put_in(state.units["m1"], thornling)
    state = %{state | turn_number: 0}
    {:ok, %{state: next}} = Spellslingers.command(state, first, :pass, context(r, first))
    assert next.units[second].hp == 100 - 14
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

    # Bots pick their books at once and never block: the human's Ready is enough to begin.
    assert Enum.all?(state.turn_order -- ["a"], &(length(state.books[&1]) == 2))
    {:ok, %{state: state}} = Spellslingers.command(state, "a", {:choose_book, "geo"}, context(r))
    {:ok, %{state: state}} = Spellslingers.command(state, "a", {:choose_book, "sky"}, context(r))
    assert state.phase == :arena_books
    {:ok, %{state: state}} = Spellslingers.command(state, "a", :toggle_ready, context(r))
    assert state.phase == :arena_aim
    state = if state.current_id == "a", do: pass(state, r), else: state
    bot = state.current_id
    assert "bot-" <> _ = bot

    # A bot thinks, walks a step per tick, then casts.
    state =
      Enum.reduce_while(1..60, state, fn _, state ->
        {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_bot, context(r))
        if state.phase == :arena_resolve, do: {:halt, state}, else: {:cont, state}
      end)

    assert state.phase == :arena_resolve
    assert state.last_cast.caster_id == bot
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
             Spellslingers.command(state, first, {:cast, "ledge", 45, 100}, context(r, first))

    assert {:error, :out_of_range} =
             Spellslingers.command(
               state,
               first,
               {:place, "ledge", me.x + 150, y},
               context(r, first)
             )

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:place, "ledge", x, y}, context(r, first))

    assert Terrain.solid?(cast.terrain, x, y)
    refute Terrain.solid?(state.terrain, x, y)
  end

  test "an earthquake with no ground left still hurts every other wizard" do
    {state, r} = started()
    [first, second] = state.turn_order
    {width, height} = Spellslingers.dimensions()
    state = %{state | terrain: :binary.copy(<<0>>, width * height), books: %{first => ["geo"]}}

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "quake", 0, 0}, context(r, first))

    assert cast.units[second].hp < 100
    assert cast.damage_dealt[first] > 0
  end

  test "the opening turn skips a wizard who disconnected while choosing books" do
    r = roster(["a", "b", "c"])

    state =
      Enum.reduce(["a", "b", "c"], Spellslingers.new(), fn id, state ->
        {:ok, %{state: state}} = Spellslingers.admit_member(state, r.players[id], context(r))
        state
      end)

    {:ok, %{state: state}} = Spellslingers.start(state, %{seed: 42}, context(r))
    [gone | rest] = state.turn_order
    away = roster(["a", "b", "c"], [gone])

    {:ok, %{state: state}} = Spellslingers.timeout(state, :arena_books, context(away))

    assert state.current_id == hd(rest)
  end

  test "a winning shot stays a win even if the tide would drown the winner" do
    {state, r} = started()
    [first, second] = state.turn_order
    me = %{state.units[first] | y: state.water_level - 1}

    state = %{
      state
      | phase: :arena_resolve,
        current_id: first,
        rise_after: 0,
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
    state = %{state | turn_number: 10}

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
        |> Spells.fx_with_meteor(b.x + 0.5, 0, "surge")
        |> Spells.fx_with_meteor(a.x + 0.5, 40, "surge")
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

  test "chain lightning does not arc back into the wizard it struck" do
    {state, r} = started()
    [first, second] = state.turn_order
    state = clear_line(%{state | wind: 0, books: %{first => ["storm"]}}, first, second)
    {:cast, _, angle, _} = lance_at(state, first, second)

    {:ok, %{state: cast}} =
      Spellslingers.command(state, first, {:cast, "chain", angle, 100}, context(r, first))

    assert cast.units[second].hp < 100
    assert cast.last_cast.beams == []
  end

  defp pass(state, r) do
    {:ok, %{state: state}} = Spellslingers.command(state, "a", :pass, context(r, "a"))
    state
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
