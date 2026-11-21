defmodule Flamingo.GameModes.Spellslingers do
  @moduledoc """
  Pure transitions for Spellslingers, a turn-based artillery duel on destructible
  terrain.

  Each player is a wizard. A duel opens with every wizard choosing a spellbook,
  which adds four spells to the two every wizard knows. On their turn a wizard may
  walk a little, then casts one spell: bolts that blast craters and knock wizards
  flying, spells that raise or tunnel through land, summoned minions that fight
  for their owner, and wilder magic. Crates drop between turns, wild-magic surges
  strike at random, and the sea rises late in the duel. The last wizard standing
  wins.

  The terrain is a `@width` by `@height` grid stored as one byte per cell. All
  physics runs here; clients receive the flight paths of each cast and animate them.
  """

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Bots, Catalog, Rng, Spells, Terrain, Units}
  alias Flamingo.GameSettings

  @book_ids Catalog.book_ids()

  defdelegate spells, to: Catalog
  defdelegate books, to: Catalog
  defdelegate maps, to: Catalog
  def dimensions, do: {@width, @height}

  def new do
    %{
      phase: :lobby,
      turn_length: 40,
      arena_map: "random",
      map_id: nil,
      participants: %{},
      players: %{},
      player_order: [],
      host_id: nil,
      terrain: <<>>,
      water_level: @initial_water,
      units: %{},
      crates: [],
      crate_count: 0,
      books: %{},
      turn_order: [],
      current_id: nil,
      turn_number: 0,
      rise_after: 0,
      wind: 0,
      walk_left: @walk_budget,
      cooldowns: %{},
      cast_this_turn: [],
      quick_used: false,
      bot_plan: nil,
      last_cast: nil,
      cast_count: 0,
      minion_count: 0,
      events: [],
      eliminated: [],
      damage_dealt: %{},
      rng: nil,
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

  def connection_changed(%{phase: :arena_books} = state, _id, :offline, context),
    do: maybe_begin_duel(state, context)

  def connection_changed(%{phase: :arena_aim, current_id: id} = state, id, :offline, context),
    do: end_turn(state, context)

  def connection_changed(state, _id, _status, _context), do: ok(state)

  def remove_member(state, id, _removed, context) do
    host_id = if state.host_id == id, do: context.roster.host_id, else: state.host_id
    state = %{state | participants: Map.delete(state.participants, id), host_id: host_id}

    if state.phase in [:arena_books, :arena_aim, :arena_resolve] and Units.alive?(state, id) do
      state = state |> forfeit(id) |> Units.log("#{Units.player_name(state, id)} left the arena.")

      cond do
        winner_decided?(state) -> finish(state)
        state.phase == :arena_books -> maybe_begin_duel(state, context)
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
    bot_ids = if is_integer(bots) and bots > 0, do: Enum.map(1..bots, &"bot-#{&1}"), else: []

    with true <- context.actor_id == roster.host_id || {:error, :not_host},
         true <- (is_integer(bots) and bots in 0..@max_bots) || {:error, :invalid_bots},
         true <- length(order) + bots >= 2 || {:error, :not_enough_players},
         true <-
           turn_length in GameSettings.turn_length_range() || {:error, :invalid_turn_length},
         true <- arena_map in ["random" | Catalog.map_ids()] || {:error, :invalid_arena_map} do
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
        | phase: :arena_books,
          turn_length: turn_length,
          arena_map: arena_map,
          map_id: map_id,
          participants:
            Map.new(roster.player_order, &{&1, if(&1 in order, do: :active, else: :spectator)})
            |> Map.merge(Map.new(bot_ids, &{&1, :active})),
          players: players,
          player_order: turn_order,
          host_id: roster.host_id,
          terrain: terrain,
          turn_order: turn_order,
          current_id: hd(turn_order),
          turn_number: 0,
          rise_after: length(turn_order) * 7,
          wind: wind,
          cooldowns: Map.new(turn_order, &{&1, %{}}),
          damage_dealt: Map.new(turn_order, &{&1, 0}),
          rng: rng
      }

      state =
        state
        |> Units.place_wizards()
        |> Units.log("The arena is #{map_name(map_id)}. Choose your spellbooks!")

      ok(state, :ok, [{:schedule_phase_timeout, :arena_books, @book_ms}])
    end
  end

  def command(%{phase: :arena_books} = state, actor, {:choose_book, book}, context)
      when book in @book_ids do
    if Map.get(state.participants, actor) == :active and Units.alive?(state, actor) do
      mine = Map.get(state.books, actor, [])

      mine =
        cond do
          book in mine -> List.delete(mine, book)
          length(mine) >= 2 -> tl(mine) ++ [book]
          true -> mine ++ [book]
        end

      state
      |> Map.update!(:books, &Map.put(&1, actor, mine))
      |> maybe_begin_duel(context)
    else
      {:error, :spectator}
    end
  end

  def command(_state, _actor, {:choose_book, _}, _context), do: {:error, :invalid_book}

  def command(%{phase: :arena_aim} = state, actor, {:walk, dir}, context) when dir in [-1, 1] do
    with :ok <- check_turn(state, actor), do: walk(state, actor, dir, context)
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
      |> Units.collect_crates()
      |> ok()
    end
  end

  def command(%{phase: :arena_aim} = state, actor, {:cast, spell_id, angle, power}, _context)
      when is_binary(spell_id) and is_number(angle) and is_number(power) do
    with :ok <- check_turn(state, actor),
         {:ok, spell} <- Catalog.fetch_spell(spell_id),
         true <- spell.id in spellbook(state, actor) || {:error, :unknown_spell},
         true <- spell_ready?(state, actor, spell.id) || {:error, :spell_cooling_down},
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
         {:ok, spell} <- Catalog.fetch_spell(spell_id),
         true <- spell.place || {:error, :unknown_spell},
         true <- spell.id in spellbook(state, actor) || {:error, :unknown_spell},
         true <- spell_ready?(state, actor, spell.id) || {:error, :spell_cooling_down},
         true <- (x >= 0 and x < @width and y >= 0 and y < @height) || {:error, :invalid_aim},
         true <- Spells.in_place_range?(state, actor, x, y) || {:error, :out_of_range} do
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
             (is_tuple(command) and elem(command, 0) in [:walk, :rise, :cast, :place]),
      do: {:error, :not_your_turn}

  def command(_state, _actor, _command, _context), do: {:error, :invalid_command}

  def timeout(%{phase: :arena_books} = state, :arena_books, context),
    do: begin_duel(state, context)

  def timeout(%{phase: :arena_aim} = state, :arena_turn, context) do
    state
    |> Units.log("#{Units.player_name(state, state.current_id)} ran out of time.")
    |> end_turn(context)
  end

  def timeout(%{phase: :arena_resolve} = state, :arena_resolve, context),
    do: end_turn(state, context)

  def timeout(%{phase: :arena_resolve} = state, :arena_surge, context),
    do: start_turn(state, state.current_id, nil, context)

  def timeout(%{phase: :arena_aim, current_id: bot} = state, :arena_bot, context) do
    if Bots.bot?(state, bot) and Units.alive?(state, bot) do
      ready = Enum.filter(spellbook(state, bot), &spell_ready?(state, bot, &1))
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
      player_order: state.player_order,
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
      walk_budget: @walk_budget,
      width: @width,
      height: @height,
      water_level: state.water_level,
      terrain: Terrain.encode_terrain(state.terrain),
      units: state.units |> Map.values() |> Enum.sort_by(& &1.id),
      crates: state.crates,
      books: Catalog.books(),
      chosen_books: state.books,
      my_spells: spellbook(state, viewer),
      quick_used: state.quick_used,
      cooldowns: Map.get(state.cooldowns, viewer, %{}),
      spells: Enum.map(Catalog.spells(), &Map.drop(&1, [:icon])),
      last_cast: state.last_cast,
      events: state.events,
      physics: %{
        dt: @dt,
        gravity: @gravity,
        max_speed: @max_speed,
        wind_accel: @wind_accel,
        playback_speed: @playback_speed,
        place_range: @place_range
      },
      final_result: state.final_result
    }
  end

  ## Spellbooks and turns

  @doc "The spell ids a player can cast: the core spells, then their book's."
  def spellbook(state, id) do
    chosen = Map.get(state.books, id, [])

    Catalog.core() ++
      Enum.flat_map(chosen, fn book -> Enum.find(Catalog.books(), &(&1.id == book)).spells end)
  end

  defp maybe_begin_duel(state, context) do
    waiting =
      Enum.filter(state.turn_order, fn id ->
        Units.alive?(state, id) and length(Map.get(state.books, id, [])) < 2 and
          match?(%{connected: true}, context.roster.players[id])
      end)

    if waiting == [], do: begin_duel(state, context), else: ok(state)
  end

  defp begin_duel(state, context) do
    {books, rng} =
      Enum.reduce(state.turn_order, {state.books, state.rng}, fn id, {books, rng} ->
        {mine, rng} = fill_books(Map.get(books, id, []), rng)
        {Map.put(books, id, mine), rng}
      end)

    # The same rule as every later turn: the first wizard who is still here.
    first = next_turn(state, List.last(state.turn_order), context)

    state =
      %{
        state
        | books: books,
          rng: rng,
          phase: :arena_aim,
          current_id: first,
          turn_number: 1,
          walk_left: @walk_budget,
          cast_this_turn: [],
          quick_used: false,
          bot_plan: nil
      }
      |> Units.log("The duel begins! #{Units.player_name(state, first)} casts first.")

    ok(state, :ok, aim_timers(state))
  end

  defp fill_books(mine, rng) when length(mine) >= 2, do: {mine, rng}

  defp fill_books(mine, rng) do
    {book, rng} = Rng.pick(Catalog.book_ids() -- mine, rng)
    fill_books(mine ++ [book], rng)
  end

  defp clear_ward(state, id) do
    case state.units[id] do
      %{} = unit -> Units.put_unit(state, Map.put(unit, :ward, 0))
      nil -> state
    end
  end

  defp tick_float(state, owner) do
    case state.units[owner] do
      %{float: float} = unit when float > 0 ->
        unit = %{unit | float: float - 1}

        # Levitation ends with a gentle landing, never fall damage.
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

  # Ends the current wizard's turn. Each hazard stage can settle the duel, and a
  # settled duel ends before any later hazard runs, so a winning shot stays a win.
  def end_turn(state, context) do
    owner = state.current_id

    with {:cont, state} <- unless_won(state),
         {:cont, state} <-
           state |> Spells.minions_act(owner) |> Units.resolve_deaths() |> unless_won(),
         {:cont, state} <-
           state
           |> tick_float(owner)
           |> tick_cooldowns(owner)
           |> rise_tide()
           |> Units.resolve_deaths()
           |> unless_won() do
      {surge, state} = Spells.roll_surge(state)
      state = Spells.surge_before(state, surge)

      # Meteors play out like a cast before the next wizard's clock starts.
      if surge == :meteors,
        do:
          ok(%{state | phase: :arena_resolve}, :ok, [
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
            walk_left: @walk_budget,
            cast_this_turn: [],
            quick_used: false,
            bot_plan: nil
        }
        |> clear_ward(next)
        |> Spells.surge_after(surge)
        |> Units.maybe_drop_crate()

      ok(state, :ok, aim_timers(state))
    end
  end

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

  defp tick_cooldowns(state, owner) do
    just_cast = state.cast_this_turn

    cooldowns =
      Map.update(state.cooldowns, owner, %{}, fn spells ->
        Map.new(spells, fn {spell, turns} ->
          if spell in just_cast, do: {spell, turns}, else: {spell, max(turns - 1, 0)}
        end)
      end)

    %{state | cooldowns: cooldowns}
  end

  defp rise_tide(state) do
    if state.turn_number >= state.rise_after do
      %{state | water_level: max(state.water_level - 2, 10)} |> Units.log("The tide rises!")
    else
      state
    end
  end

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

      state =
        %{state | walk_left: state.walk_left - 1}
        |> Units.put_unit(wizard)
        |> Units.fall_damage(wizard.id, fall)
        |> Units.collect_crates()
        |> Units.resolve_deaths()

      cond do
        winner_decided?(state) -> finish(state)
        not Units.alive?(state, actor) -> end_turn(state, context)
        true -> ok(state)
      end
    end
  end

  ## Bots

  # Bots decide in `Bots`; their moves go through the same rules as a player's.
  defp apply_bot_move({{:plan, ward?, delay}, state}, bot, context) do
    state =
      case ward? && command(state, bot, {:cast, "ward", 0, 0}, context) do
        {:ok, %{state: warded}} -> warded
        _ -> state
      end

    ok(state, :ok, [{:schedule_hint_timeout, :arena_bot, delay}])
  end

  defp apply_bot_move({{:walk, dir}, state}, bot, context) do
    case walk(state, bot, dir, context) do
      {:ok, %{state: %{phase: :arena_aim, current_id: ^bot}} = result} ->
        {:ok, %{result | timers: result.timers ++ [{:schedule_hint_timeout, :arena_bot, 90}]}}

      {:ok, result} ->
        {:ok, result}

      {:error, _blocked} ->
        ok(%{state | bot_plan: %{steps: []}}, :ok, [{:schedule_hint_timeout, :arena_bot, 200}])
    end
  end

  defp apply_bot_move({{:cast, spell, angle, power}, state}, bot, context) do
    with {:error, _} <- command(state, bot, {:cast, spell, angle, power}, context),
         do: end_turn(state, context)
  end

  defp apply_bot_move({{:place, spell, x, y}, state}, bot, context) do
    with {:error, _} <- command(state, bot, {:place, spell, x, y}, context),
         do: end_turn(state, context)
  end

  defp apply_bot_move({:pass, state}, _bot, context), do: end_turn(state, context)

  def spell_ready?(state, actor, spell_id),
    do: Map.get(Map.get(state.cooldowns, actor, %{}), spell_id, 0) == 0

  def winner_decided?(state), do: Enum.count(state.turn_order, &Units.alive?(state, &1)) <= 1

  def finish(state) do
    survivors = Enum.filter(state.turn_order, &Units.alive?(state, &1))
    winner = List.first(survivors)

    result = %{
      winner_id: winner,
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
    ok(state, :ok, [:cancel_phase_timeout, :cancel_hint_timeout])
  end

  ## Wild magic and crates

  ## Casting

  def cast(state, actor, spell, angle, power, target \\ nil) do
    state = %{
      state
      | cast_this_turn: [spell.id | state.cast_this_turn],
        cooldowns:
          if(spell.cooldown > 0,
            do: put_in(state.cooldowns, [actor, spell.id], spell.cooldown),
            else: state.cooldowns
          )
    }

    state = Units.log(state, "#{Units.player_name(state, actor)} casts #{spell.name}.")
    before = state
    fx = Spells.effect(spell.effect, Spells.new_fx(state, target), actor, spell, angle, power)
    {state, knocks} = Spells.resolve_fx(fx.state, fx)
    state = Spells.record_cast(state, before, actor, spell.id, fx, knocks)
    %{last_cast: cast} = state

    if spell.quick do
      # Quick spells leave the turn open for walking and one more cast.
      ok(%{state | quick_used: true})
    else
      ok(%{state | phase: :arena_resolve}, :ok, [
        {:schedule_phase_timeout, :arena_resolve, cast.duration_ms + 1200}
      ])
    end
  end

  ## Knockback

  ## Minions

  ## Units and movement

  defp forfeit(state, id) do
    case state.units[id] do
      %{dead: false} = unit ->
        state
        |> Units.put_unit(%{unit | hp: 0, dead: true})
        |> Map.update!(:eliminated, &[id | &1])
        |> Units.remove_minions(id)

      _ ->
        state
    end
  end

  defp map_name(id),
    do: Enum.find_value(Catalog.maps(), "a mystery", fn {map, name} -> if map == id, do: name end)

  ## Terrain

  def ok(state, reply \\ :ok, timers \\ []) do
    status = if state.phase == :game_ended, do: {:finished, state.final_result}, else: :continue

    {:ok,
     %{
       state: state,
       reply: reply,
       timers: timers,
       status: status,
       drawing_delta: nil,
       drawing_scope: nil
     }}
  end
end
