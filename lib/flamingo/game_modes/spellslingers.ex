defmodule Flamingo.GameModes.Spellslingers do
  @moduledoc """
  Pure transitions for Spellslingers, a turn-based artillery duel on destructible
  terrain.

  Each player is a wizard, and every wizard carries the same arsenal, as in Worms:
  each spell has its ammo and some unlock after a few turns. On their turn a wizard may
  walk, jump or fly a little, then casts one spell, and gets a few seconds to retreat
  before the turn passes. Crates drop between turns, wild-magic surges strike at
  random, spell crates add ammo, and after a while sudden death drops everyone to one
  health while the sea rises. The last wizard standing wins.

  The terrain is a grid of one byte per cell, sized in `Rules`. All physics runs
  on the server; clients receive the flight paths of each cast and animate them.
  """

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{
    Bots,
    Catalog,
    Crates,
    Physics,
    Rng,
    Rules,
    Spells,
    Surges,
    Terrain,
    Units
  }

  alias Flamingo.GameSettings

  defdelegate spells, to: Catalog
  defdelegate maps, to: Catalog
  defdelegate spell(id), to: Catalog

  @doc "The most AI wizards a host can add."
  def max_bots, do: @max_bots
  defdelegate tuning, to: Rules
  def dimensions, do: {@width, @height}

  def new do
    %{
      phase: :lobby,
      turn_length: 40,
      map_id: nil,
      participants: %{},
      players: %{},
      host_id: nil,
      terrain: <<>>,
      water_level: @initial_water,
      units: %{},
      crates: [],
      crate_count: 0,
      # Ammo left of each limited arsenal spell, by wizard.
      ammo: %{},
      turn_order: [],
      current_id: nil,
      turn_number: 0,
      # The turn sudden death strikes, and whether it has.
      sudden_after: 0,
      sudden_death: false,
      wind: 0,
      walk_left: 0,
      last_jump: nil,
      tuning: Rules.default_tuning(),
      # Turns each wizard has finished, which unlocks the bigger spells.
      turns_taken: %{},
      quick_used: false,
      # After a cast the wizard may still move for a few seconds, but not cast.
      retreat: false,
      # Blast runes waiting for their caster's turn to end.
      runes: [],
      bot_plan: nil,
      # The shot a bot is lining up, shown to everyone before it fires.
      bot_aim: nil,
      last_cast: nil,
      cast_count: 0,
      events: [],
      eliminated: [],
      damage_dealt: %{},
      forfeited: [],
      rng: nil,
      # What the duel was started with, so the host can call a rematch.
      settings: nil,
      final_result: nil
    }
  end

  ## Room callbacks

  def admit_member(state, %{id: id}, context) do
    participation = if state.phase == :lobby, do: :active, else: :spectator

    ok(%{
      state
      | participants: Map.put(state.participants, id, participation),
        host_id: state.host_id || context.roster.host_id
    })
  end

  def connection_changed(state, _id, _status, _context), do: ok(state)

  def remove_member(state, id, _removed, context) do
    host_id = if state.host_id == id, do: context.roster.host_id, else: state.host_id
    state = %{state | participants: Map.delete(state.participants, id), host_id: host_id}

    if state.phase in [:arena_aim, :arena_resolve] and Units.alive?(state, id) do
      state = %{state | forfeited: [id | state.forfeited]}
      state = state |> forfeit(id) |> Units.log("#{Units.player_name(state, id)} left the arena.")

      cond do
        winner_decided?(state) -> finish(state)
        state.current_id == id and state.phase == :arena_aim -> end_turn(state, context)
        true -> ok(state)
      end
    else
      ok(state)
    end
  end

  def start(%{phase: phase}, _settings, _context) when phase not in [:lobby, :game_ended],
    do: {:error, :game_in_progress}

  def start(state, settings, context) do
    roster = context.roster
    order = Enum.filter(roster.player_order, &match?(%{connected: true}, roster.players[&1]))
    turn_length = Map.get(settings, :turn_length, state.turn_length)
    arena_map = Map.get(settings, :arena_map, "random")
    bots = Map.get(settings, :bots, 0)

    with true <- context.actor_id == roster.host_id || {:error, :not_host},
         true <- (is_integer(bots) and bots in 0..@max_bots) || {:error, :invalid_bots},
         true <- length(order) + bots >= 2 || {:error, :not_enough_players},
         true <-
           turn_length in GameSettings.turn_length_range() || {:error, :invalid_turn_length},
         true <- arena_map in ["random" | Catalog.map_ids()] || {:error, :invalid_arena_map} do
      bot_ids = for n <- 1..bots//1, do: "bot-#{n}"

      # Tests pass a fixed seed; real games roll their own.
      rng =
        :rand.seed_s(
          :exsss,
          Map.get_lazy(settings, :seed, fn -> :rand.uniform(1_000_000_000) end)
        )

      {map_id, rng} =
        if arena_map == "random", do: Rng.pick(Catalog.map_ids(), rng), else: {arena_map, rng}

      {terrain, rng} = Terrain.generate_terrain(map_id, rng)
      {turn_order, rng} = Rng.shuffle(order ++ bot_ids, rng)
      {wind, rng} = Rng.roll_wind(rng)

      players =
        turn_order
        |> Enum.with_index()
        |> Map.new(fn {id, index} ->
          player =
            roster.players[id] ||
              %{name: "#{Bots.bot_name(id)} (bot)", avatar: Bots.bot_avatar(id), bot: true}

          {id,
           %{
             id: id,
             name: player.name,
             avatar: Map.get(player, :avatar),
             bot: Map.get(player, :bot, false),
             color: Enum.at(@palette, rem(index, length(@palette)))
           }}
        end)

      state = %{
        new()
        | phase: :arena_aim,
          turn_length: turn_length,
          map_id: map_id,
          participants:
            Map.new(roster.player_order, &{&1, if(&1 in order, do: :active, else: :spectator)})
            |> Map.merge(Map.new(bot_ids, &{&1, :active})),
          players: players,
          host_id: roster.host_id,
          terrain: terrain,
          turn_order: turn_order,
          current_id: hd(turn_order),
          turn_number: 0,
          sudden_after: length(turn_order) * 8,
          wind: wind,
          ammo: Map.new(turn_order, &{&1, Catalog.starting_ammo()}),
          damage_dealt: Map.new(turn_order, &{&1, 0}),
          rng: rng,
          settings: Map.delete(settings, :seed)
      }

      state
      |> Units.place_wizards()
      |> Units.log("The arena is #{map_name(map_id)}.")
      |> begin_duel(context)
    end
  end

  # Dev tuning: the LiveView only sends these for allowlisted players. Values
  # are clamped to each number's range and apply from the next use onwards.
  def command(state, actor, {:tune, key, value}, _context) when is_number(value) do
    case Enum.find(Rules.tuning(), &(Atom.to_string(&1.key) == key)) do
      nil ->
        {:error, :invalid_command}

      %{key: key, label: label, min: low, max: high, step: step} ->
        value = value |> max(low) |> min(high)
        value = if is_integer(step), do: round(value), else: value * 1.0

        state
        |> put_in([:tuning, key], value)
        |> Units.log("#{Units.player_name(state, actor)} set #{label} to #{value}.")
        |> ok()
    end
  end

  def command(state, actor, :reset_tuning, _context) do
    %{state | tuning: Rules.default_tuning()}
    |> Units.log("#{Units.player_name(state, actor)} restored the normal rules.")
    |> ok()
  end

  def command(%{phase: :arena_aim} = state, actor, {:walk, dir}, context) when dir in [-1, 1] do
    with :ok <- check_turn(state, actor), do: walk(state, actor, dir, context)
  end

  def command(%{phase: :arena_aim} = state, actor, {:jump, kind, dir}, context)
      when kind in [:high, :long] and dir in [-1, 1] do
    with :ok <- check_turn(state, actor), do: jump(state, actor, kind, dir, context)
  end

  def command(%{phase: :arena_aim} = state, actor, {:rise, dir}, _context) when dir in [-1, 1] do
    with :ok <- check_turn(state, actor),
         true <- state.walk_left > 0 || {:error, :no_steps_left},
         wizard = state.units[actor],
         true <- Map.get(wizard, :float, 0) > 0 || {:error, :not_floating},
         y = wizard.y - dir,
         true <-
           (y >= 3 and y < state.water_level and not Units.blocked?(state, wizard, wizard.x, y)) ||
             {:error, :blocked} do
      %{state | walk_left: state.walk_left - 1}
      |> Units.put_unit(%{wizard | y: y})
      |> Crates.collect_crates()
      |> ok()
    end
  end

  # Once the duel is over the host can go again straight away, with the same settings.
  # Cast numbers carry on, so clients never mistake the new game's first cast for one seen.
  def command(%{phase: :game_ended} = state, actor, :rematch, context) do
    with {:ok, result} <- start(state, state.settings || %{}, Map.put(context, :actor_id, actor)),
         do: {:ok, %{result | state: %{result.state | cast_count: state.cast_count}}}
  end

  def command(%{phase: :arena_aim} = state, actor, {:cast, spell_id, angle, power}, _context)
      when is_binary(spell_id) and is_number(angle) and is_number(power) do
    with :ok <- check_turn(state, actor),
         true <- not state.retreat || {:error, :retreating},
         {:ok, spell} <- Catalog.fetch_spell(spell_id),
         :ok <- check_ready(state, actor, spell.id),
         true <- not spell.place || {:error, :place_only},
         true <- not (spell.quick and state.quick_used) || {:error, :quick_used},
         true <- (angle >= -180 and angle <= 360) || {:error, :invalid_aim},
         true <- (power >= 0 and power <= 100) || {:error, :invalid_aim} do
      cast(state, actor, spell, angle, power)
    end
  end

  # Placed spells conjure at a point instead of being thrown.
  def command(%{phase: :arena_aim} = state, actor, {:place, spell_id, x, y}, _context)
      when is_binary(spell_id) and is_number(x) and is_number(y) do
    with :ok <- check_turn(state, actor),
         true <- not state.retreat || {:error, :retreating},
         {:ok, spell} <- Catalog.fetch_spell(spell_id),
         true <- spell.place || {:error, :unknown_spell},
         :ok <- check_ready(state, actor, spell.id),
         true <- (x >= 0 and x < @width and y >= 0 and y < @height) || {:error, :invalid_aim},
         true <-
           spell.sky || Spells.in_place_range?(state, actor, x, y) || {:error, :out_of_range} do
      cast(state, actor, spell, 0, 0, {x * 1.0, y * 1.0})
    end
  end

  def command(%{phase: :arena_aim} = state, actor, :pass, context) do
    with :ok <- check_turn(state, actor) do
      state |> Units.log("#{Units.player_name(state, actor)} passes.") |> end_turn(context)
    end
  end

  def command(_state, _actor, command, _context)
      when command == :pass or
             (is_tuple(command) and elem(command, 0) in [:walk, :jump, :rise, :cast, :place]),
      do: {:error, :not_your_turn}

  def command(_state, _actor, _command, _context), do: {:error, :invalid_command}

  def timeout(%{phase: :arena_aim} = state, :arena_turn, context) do
    state
    |> Units.log("#{Units.player_name(state, state.current_id)} ran out of time.")
    |> end_turn(context)
  end

  # The cast has played out: the caster gets a few seconds to run before the turn passes.
  def timeout(%{phase: :arena_resolve} = state, :arena_resolve, context) do
    caster = state.current_id

    if winner_decided?(state) or not Units.alive?(state, caster) do
      end_turn(state, context)
    else
      ms = if Bots.bot?(state, caster), do: @bot_retreat_ms, else: @retreat_ms

      %{state | phase: :arena_aim, retreat: true, walk_left: max(state.walk_left, 15)}
      |> ok([:cancel_hint_timeout, {:schedule_phase_timeout, :arena_retreat, ms}])
    end
  end

  def timeout(%{phase: :arena_aim, retreat: true} = state, :arena_retreat, context),
    do: end_turn(state, context)

  # The caster's blast runes have gone off; the turn ends as usual from here.
  def timeout(%{phase: :arena_resolve} = state, :arena_runes, context),
    do: finish_turn(state, context)

  def timeout(%{phase: :arena_resolve} = state, :arena_surge, context),
    do: start_turn(state, state.current_id, nil, context)

  # A bot that has shown its aim lets fly.
  def timeout(%{phase: :arena_aim, bot_aim: %{} = aim} = state, :arena_bot, context) do
    state = %{state | bot_aim: nil}

    command =
      if Map.has_key?(aim, :x),
        do: {:place, aim.spell, aim.x, aim.y},
        else: {:cast, aim.spell, aim.angle, aim.power}

    with {:error, _} <- command(state, state.current_id, command, context),
         do: end_turn(state, context)
  end

  def timeout(%{phase: :arena_aim, retreat: false, current_id: bot} = state, :arena_bot, context) do
    if Bots.bot?(state, bot) and Units.alive?(state, bot) do
      ready = Enum.filter(Catalog.arsenal_ids(), &spell_ready?(state, bot, &1))
      state |> Bots.next_move(ready) |> apply_bot_move(bot, context)
    else
      :ignored
    end
  end

  def timeout(_state, _key, _context), do: :ignored

  def view(state, viewer, roster) do
    %{
      mode: :spellslingers,
      phase: state.phase,
      viewer_id: viewer,
      participation: Map.get(state.participants, viewer, :spectator),
      players: state.players,
      player_order: state.turn_order,
      host_id: state.host_id || roster.host_id,
      online:
        Map.new(roster.players, fn {id, player} -> {id, player.connected} end)
        |> Map.merge(for({id, %{bot: true}} <- state.players, into: %{}, do: {id, true})),
      turn_length: state.turn_length,
      current_id: state.current_id,
      turn_number: state.turn_number,
      map_id: state.map_id,
      map_name: map_name(state.map_id),
      wind: state.wind,
      walk_left: state.walk_left,
      walk_budget: state.tuning.walk_budget,
      jump_cost: @jump_cost,
      last_jump: state.last_jump,
      tuning: state.tuning,
      tuned?: state.tuning != Rules.default_tuning(),
      width: @width,
      height: @height,
      water_level: state.water_level,
      terrain: Terrain.encode_terrain(state.terrain),
      units: state.units |> Map.values() |> Enum.sort_by(& &1.id),
      crates: state.crates,
      runes: state.runes,
      my_spells: Catalog.arsenal_ids(),
      ammo: Map.get(state.ammo, viewer, %{}),
      quick_used: state.quick_used,
      retreat: state.retreat,
      bot_aim: state.bot_aim,
      sudden_death: state.sudden_death,
      locked: locked(state, viewer),
      spells: Catalog.spells(),
      last_cast: state.last_cast,
      events: state.events,
      physics: %{
        dt: @dt,
        gravity: state.tuning.gravity,
        max_speed: @max_speed,
        wind_accel: state.tuning.wind_accel,
        playback_speed: @playback_speed,
        grand_intro_ms: @grand_intro_ms,
        place_range: state.tuning.place_range,
        max_climb: @max_climb
      },
      final_result: state.final_result
    }
  end

  ## Turns

  defp begin_duel(state, context) do
    # The same rule as every later turn: the first wizard who is still here.
    first = next_turn(state, List.last(state.turn_order), context)

    state =
      %{
        state
        | phase: :arena_aim,
          current_id: first,
          turn_number: 1,
          walk_left: state.tuning.walk_budget,
          quick_used: false,
          bot_plan: nil
      }
      |> Units.log("The duel begins! #{Units.player_name(state, first)} goes first.")

    ok(state, aim_timers(state))
  end

  defp tick_float(state, owner) do
    case state.units[owner] do
      %{float: float} = unit when float > 0 ->
        unit = %{unit | float: float - 1}

        # The broom sets its rider down gently, never with fall damage.
        unit = if unit.float == 0, do: elem(Units.do_settle(state, unit), 0), else: unit
        Units.put_unit(state, unit)

      _ ->
        state
    end
  end

  defp check_turn(state, actor) do
    cond do
      Map.get(state.participants, actor) != :active -> {:error, :spectator}
      state.current_id != actor -> {:error, :not_your_turn}
      not Units.alive?(state, actor) -> {:error, :not_your_turn}
      true -> :ok
    end
  end

  # Ends the current wizard's turn: first their blast runes go off, played out like a
  # cast, then the rest of the turn's end.
  defp end_turn(state, context) do
    state = %{state | retreat: false, bot_aim: nil}

    if Enum.any?(state.runes, &(&1.owner == state.current_id)) do
      state = Spells.detonate_runes(state, state.current_id)

      ok(%{state | phase: :arena_resolve}, [
        :cancel_hint_timeout,
        {:schedule_phase_timeout, :arena_runes, state.last_cast.duration_ms + 900}
      ])
    else
      finish_turn(state, context)
    end
  end

  # Each hazard stage can settle the duel, and a settled duel ends before any later
  # hazard runs, so a winning shot stays a win.
  defp finish_turn(state, context) do
    owner = state.current_id

    with {:cont, state} <- unless_won(state),
         {:cont, state} <-
           state
           |> tick_float(owner)
           |> tick_turns(owner)
           |> rise_tide()
           |> Units.resolve_deaths()
           |> unless_won() do
      {surge, state} = Surges.roll_surge(state)
      state = Surges.surge_before(state, surge)

      # Meteors play out like a cast before the next wizard's clock starts.
      if surge == :meteors,
        do:
          ok(%{state | phase: :arena_resolve}, [
            :cancel_hint_timeout,
            {:schedule_phase_timeout, :arena_surge, state.last_cast.duration_ms + 1200}
          ]),
        else: start_turn(state, owner, surge, context)
    else
      {:won, state} -> finish(state)
    end
  end

  defp unless_won(state), do: if(winner_decided?(state), do: {:won, state}, else: {:cont, state})

  defp start_turn(state, previous, surge, context) do
    if winner_decided?(state) do
      finish(state)
    else
      next = next_turn(state, previous, context)
      {wind, rng} = Rng.roll_wind(state.rng)

      state =
        %{
          state
          | phase: :arena_aim,
            current_id: next,
            turn_number: state.turn_number + 1,
            wind: wind,
            rng: rng,
            walk_left: state.tuning.walk_budget,
            quick_used: false,
            bot_plan: nil
        }
        |> Surges.surge_after(surge)
        |> Crates.maybe_drop_crate()
        |> sudden_death()

      ok(state, aim_timers(state))
    end
  end

  # Sudden death, as in Worms: every wizard drops to one health, and from now on the
  # sea rises each turn.
  defp sudden_death(%{sudden_death: false} = state)
       when state.turn_number >= state.sudden_after do
    units =
      Map.new(state.units, fn {id, unit} ->
        {id, if(Units.alive_unit?(unit), do: %{unit | hp: 1}, else: unit)}
      end)

    %{state | units: units, sudden_death: true}
    |> Units.log("SUDDEN DEATH! Everyone is down to 1 health, and the sea is rising.")
  end

  defp sudden_death(state), do: state

  defp next_turn(state, previous, context) do
    index = Enum.find_index(state.turn_order, &(&1 == previous)) || -1

    candidates =
      (Enum.drop(state.turn_order, index + 1) ++ Enum.take(state.turn_order, index + 1))
      |> Enum.filter(&Units.alive?(state, &1))

    online = Enum.filter(candidates, &online?(state, context, &1))
    List.first(online) || List.first(candidates)
  end

  defp online?(state, context, id),
    do: Bots.bot?(state, id) or match?(%{connected: true}, context.roster.players[id])

  defp tick_turns(state, owner),
    do: %{state | turns_taken: Map.update(state.turns_taken, owner, 1, &(&1 + 1))}

  defp rise_tide(%{sudden_death: true} = state),
    do: %{state | water_level: max(state.water_level - 3, 10)} |> Units.log("The sea rises!")

  defp rise_tide(state), do: state

  defp aim_timers(state) do
    turn = [
      :cancel_hint_timeout,
      {:schedule_phase_timeout, :arena_turn, state.turn_length * 1000}
    ]

    if Bots.bot?(state, state.current_id),
      do: turn ++ [{:schedule_hint_timeout, :arena_bot, @bot_think_ms}],
      else: turn
  end

  defp walk(state, actor, dir, context) do
    with true <- state.walk_left > 0 || {:error, :no_steps_left},
         {:ok, wizard} <- Units.step(state, state.units[actor], dir) do
      {wizard, fall} = Units.settle(state, wizard)

      %{state | walk_left: state.walk_left - 1}
      |> Units.put_unit(wizard)
      |> Units.fall_damage(wizard.id, fall)
      |> after_move(actor, context)
    end
  end

  # A jump spends a few steps and flies the wizard along an arc. Only a net drop
  # from where it took off can hurt, the same as walking off that ledge would.
  # A jump that comes back down where it started went nowhere, so it is refused and
  # costs nothing.
  defp jump(state, actor, kind, dir, context) do
    wizard = state.units[actor]

    with true <- state.walk_left >= @jump_cost || {:error, :no_steps_left},
         true <- Map.get(wizard, :float, 0) == 0 || {:error, :floating},
         {flown, path} = Physics.jump(state, wizard, @jumps[kind], dir),
         {landed, _} = Units.settle(state, flown),
         true <- {landed.x, landed.y} != {wizard.x, wizard.y} || {:error, :blocked} do
      path = if landed.y != flown.y, do: path ++ [{landed.x * 1.0, landed.y * 1.0}], else: path
      n = if state.last_jump, do: state.last_jump.n + 1, else: 1

      %{
        state
        | walk_left: state.walk_left - @jump_cost,
          last_jump: %{
            n: n,
            id: actor,
            path: Enum.map(path, fn {x, y} -> [Float.round(x, 2), Float.round(y, 2)] end)
          }
      }
      |> Units.put_unit(landed)
      |> Units.fall_damage(actor, max(0, landed.y - wizard.y))
      |> after_move(actor, context)
    end
  end

  defp after_move(state, actor, context) do
    state = state |> Crates.collect_crates() |> Units.resolve_deaths()

    cond do
      winner_decided?(state) -> finish(state)
      not Units.alive?(state, actor) -> end_turn(state, context)
      true -> ok(state)
    end
  end

  ## Bots

  # Bots decide in `Bots`; their moves go through the same rules as a player's.
  defp apply_bot_move({{:plan, delay}, state}, _bot, _context),
    do: ok(state, [{:schedule_hint_timeout, :arena_bot, delay}])

  defp apply_bot_move({{:walk, dir}, state}, bot, context) do
    case walk(state, bot, dir, context) do
      {:ok, %{state: %{phase: :arena_aim, current_id: ^bot}} = result} ->
        {:ok, %{result | timers: result.timers ++ [{:schedule_hint_timeout, :arena_bot, 90}]}}

      {:ok, result} ->
        {:ok, result}

      {:error, _blocked} ->
        ok(%{state | bot_plan: %{steps: []}}, [{:schedule_hint_timeout, :arena_bot, 200}])
    end
  end

  # Spells cast on picking go at once; anything aimed is shown first (see `timeout/3`).
  defp apply_bot_move({{:cast, spell, angle, power}, state}, bot, context) do
    if Catalog.spell(spell).input == "instant" do
      with {:error, _} <- command(state, bot, {:cast, spell, angle, power}, context),
           do: end_turn(state, context)
    else
      %{state | bot_aim: %{spell: spell, angle: angle, power: power}}
      |> ok([{:schedule_hint_timeout, :arena_bot, @bot_aim_ms}])
    end
  end

  defp apply_bot_move({{:place, spell, x, y}, state}, _bot, _context) do
    %{state | bot_aim: %{spell: spell, x: x, y: y}}
    |> ok([{:schedule_hint_timeout, :arena_bot, @bot_aim_ms}])
  end

  defp apply_bot_move({:pass, state}, _bot, context), do: end_turn(state, context)

  # Spells are limited by ammo and by the turns before they unlock, nothing else.
  defp check_ready(state, actor, spell_id) do
    cond do
      unlock_left(state, actor, spell_id) > 0 -> {:error, :spell_locked}
      ammo_left(state, actor, spell_id) == 0 -> {:error, :no_ammo}
      true -> :ok
    end
  end

  defp unlock_left(state, actor, spell_id),
    do: max(Catalog.unlock(spell_id) - Map.get(state.turns_taken, actor, 0), 0)

  defp ammo_left(state, actor, spell_id),
    do: state.ammo |> Map.get(actor, %{}) |> Map.get(spell_id, :infinite)

  defp spell_ready?(state, actor, spell_id), do: check_ready(state, actor, spell_id) == :ok

  # Spells still locked for a player, with how many of their turns are left.
  defp locked(state, viewer) do
    for id <- Catalog.arsenal_ids(),
        (n = unlock_left(state, viewer, id)) > 0,
        into: %{},
        do: {id, n}
  end

  defp winner_decided?(state), do: Enum.count(state.turn_order, &Units.alive?(state, &1)) <= 1

  defp finish(state) do
    survivors = Enum.filter(state.turn_order, &Units.alive?(state, &1))
    winner = List.first(survivors)

    result = %{
      winner_id: winner,
      map_id: state.map_id,
      bots: for({id, %{bot: true}} <- state.players, do: id),
      forfeited: state.forfeited,
      standings:
        (survivors ++ state.eliminated)
        |> Enum.with_index(1)
        |> Enum.map(fn {id, place} ->
          %{id: id, place: place, damage: Map.get(state.damage_dealt, id, 0)}
        end)
    }

    message =
      if winner,
        do: "#{Units.player_name(state, winner)} wins the duel!",
        else: "Nobody survived!"

    state = %{state | phase: :game_ended, final_result: result} |> Units.log(message)
    ok(state, [:cancel_phase_timeout, :cancel_hint_timeout])
  end

  @doc """
  The saved lobby record of a finished duel, scored by damage dealt. The last
  wizard standing wins; a duel nobody survived has no winner. Wizards who left
  are kept unranked. AI wizards hold no seat, so they are never recorded, and a
  duel needs two human wizards to count.
  """
  def history(result) do
    humans = Enum.reject(result.standings, &(&1.id in result.bots))
    # Without a survivor, the last wizard to fall still did not win.
    offset = if result.winner_id, do: 0, else: 1

    %{
      details: %Flamingo.GameHistory.SpellslingersResult{map: result.map_id},
      completed?: length(humans) >= 2,
      players:
        Enum.map(humans, fn row ->
          %{
            seat_id: row.id,
            score: row.damage,
            placement: if(row.id not in result.forfeited, do: row.place + offset),
            team: nil
          }
        end),
      drawings: []
    }
  end

  ## Casting

  defp cast(state, actor, spell, angle, power, target \\ nil) do
    state = %{
      state
      | ammo:
          if(is_integer(ammo_left(state, actor, spell.id)),
            do: update_in(state.ammo, [actor, spell.id], &(&1 - 1)),
            else: state.ammo
          )
    }

    state = Units.log(state, "#{Units.player_name(state, actor)} uses #{spell.name}.")

    state =
      Spells.run(
        state,
        actor,
        spell.id,
        target,
        &Spells.effect(spell.effect, &1, actor, spell, angle, power),
        spell.grand
      )

    %{last_cast: cast} = state

    if spell.quick do
      # Quick spells leave the turn open for walking and one more cast.
      ok(%{state | quick_used: true})
    else
      ok(%{state | phase: :arena_resolve}, [
        {:schedule_phase_timeout, :arena_resolve, cast.duration_ms + 1200}
      ])
    end
  end

  ## Helpers

  defp forfeit(state, id) do
    case state.units[id] do
      %{dead: false} = unit ->
        state
        |> Units.put_unit(%{unit | hp: 0, dead: true})
        |> Map.update!(:eliminated, &[id | &1])

      _ ->
        state
    end
  end

  defp map_name(id),
    do: Enum.find_value(Catalog.maps(), "a mystery", fn {map, name} -> if map == id, do: name end)

  defp ok(state, timers \\ []) do
    status = if state.phase == :game_ended, do: {:finished, state.final_result}, else: :continue
    {:ok, %{state: state, reply: :ok, timers: timers, status: status}}
  end
end
