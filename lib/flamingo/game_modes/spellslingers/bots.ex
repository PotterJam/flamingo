defmodule Flamingo.GameModes.Spellslingers.Bots do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Catalog, Minions, Physics, Units}

  def bot?(state, id), do: match?(%{bot: true}, state.players[id])

  def bot_name(id), do: Enum.at(@bot_names, rem(bot_index(id) - 1, length(@bot_names)))

  defp bot_index("bot-" <> n), do: String.to_integer(n)

  def bot_avatar(id) do
    i = bot_index(id)

    Flamingo.Avatar.normalize(%{
      "head" => rem(i * 3, 10),
      "body" => rem(i * 7, 10),
      "legs" => rem(i * 2, 10),
      "feet" => rem(i * 5, 10),
      "head_color" => rem(i, 8),
      "body_color" => rem(i + 3, 8),
      "legs_color" => rem(i + 5, 8),
      "feet_color" => rem(i + 1, 8)
    })
  end

  @bot_attacks ~w(inferno firerain clockbomb chain frostbolt seeker cluster decay skipstone boulder napalm bonespear lance gust updraft ember)
  @bot_summons ~w(imp golem wisp thornling raisedead turret)
  @bot_walk 16

  # A bot's turn runs on the hint timer in stages: think (maybe raise a ward and pick a
  # spot), walk one cell per tick toward that spot so everyone sees it move, then cast.
  # Bots only decide; the engine applies each move through the same commands players
  # use. `ready` lists the spell ids the bot may cast right now.
  #
  # Returns {move, state}, where state carries the updated plan and rng, and move is
  # {:plan, ward?, delay_ms}, {:walk, dir}, {:cast, spell_id, angle, power},
  # {:place, spell_id, x, y} or :pass.
  def next_move(%{bot_plan: nil} = state, ready), do: think(state, ready)

  def next_move(%{bot_plan: %{steps: [dir | rest]} = plan} = state, _ready),
    do: {{:walk, dir}, %{state | bot_plan: %{plan | steps: rest}}}

  def next_move(state, ready), do: act(%{state | bot_plan: nil}, ready)

  defp think(state, ready) do
    me = state.units[state.current_id]
    enemies = bot_enemies(state, me)
    {roll, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}

    if enemies == [] do
      {:pass, state}
    else
      nearest = Enum.min_by(enemies, &unit_distance(&1, me))
      threatened? = me.hp < 75 or unit_distance(nearest, me) < 45
      ward? = threatened? and roll < 0.6 and "ward" in ready and not state.quick_used
      steps = bot_route(state, me)
      delay = if steps == [], do: 300, else: 700
      {{:plan, ward?, delay}, %{state | bot_plan: %{steps: steps}}}
    end
  end

  # Tries spots within walking range and picks the one with the best shot, preferring
  # high ground, crates, and staying clear of the sea.
  defp bot_route(state, me) do
    options =
      ([{[], me}] ++ walk_options(state, me, -1) ++ walk_options(state, me, 1))
      |> Enum.filter(fn {steps, _} -> rem(length(steps), 4) == 0 end)

    options
    |> Enum.min_by(fn {steps, unit} -> spot_score(state, unit, length(steps)) end)
    |> elem(0)
  end

  defp walk_options(state, me, dir) do
    budget = min(@bot_walk, state.walk_left)

    {_, options} =
      Enum.reduce_while(1..budget//1, {me, []}, fn i, {unit, acc} ->
        with {:ok, moved} <- Units.step(state, unit, dir),
             {moved, fall} = Units.settle(state, moved),
             true <- fall <= state.tuning.fall_safe and moved.y < state.water_level - 1 do
          {:cont, {moved, [{List.duplicate(dir, i), moved} | acc]}}
        else
          _ -> {:halt, {unit, acc}}
        end
      end)

    options
  end

  defp spot_score(state, unit, steps) do
    target = state |> bot_enemies(unit) |> Enum.min_by(&unit_distance(&1, unit))
    origin = {unit.x + 0.5, unit.y - 2.0}

    {_, _, miss} =
      bot_aim(state, origin, unit.id, Units.center(target), Catalog.spell("ember"), coarse: true)

    water = if unit.y >= state.water_level - 6, do: 25, else: 0

    crate =
      if Enum.any?(state.crates, &(abs(&1.x - unit.x) <= 2 and abs(&1.y - unit.y) <= 3)),
        do: if(unit.hp < 70, do: 30, else: 12),
        else: 0

    miss + water - crate + steps * 0.15 - (state.water_level - unit.y) * 0.05
  end

  defp act(state, ready) do
    me = state.units[state.current_id]
    enemies = bot_enemies(state, me)

    ready = Enum.reject(ready, &Catalog.spell(&1).quick)

    {roll, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}

    if enemies == [] do
      {:pass, state}
    else
      target = Enum.min_by(enemies, &unit_distance(&1, me))
      dir = if target.x > me.x, do: 1, else: -1
      {mx, my} = Units.center(me)
      summon = Enum.find(@bot_summons, &(&1 in ready))

      owned = Minions.count(state, me.id)
      grand = Enum.find(ready, &Catalog.spell(&1).grand)

      {spell_id, point, near_ok} =
        cond do
          grand && roll < 0.6 ->
            point =
              if grand == "dragon", do: {mx + dir * 6, my - 2}, else: Units.center(target)

            {grand, point, true}

          "drain" in ready and me.hp < 80 and unit_distance(target, me) < 22 ->
            {"drain", nil, true}

          "nova" in ready and unit_distance(target, me) < 12 ->
            {"nova", nil, true}

          me.hp < 45 and "bloom" in ready ->
            {"bloom", {mx, my + 1}, true}

          me.hp < 60 and "rampart" in ready and roll < 0.6 ->
            {"rampart", {mx + dir * 6, me.y + 1.0}, true}

          summon && owned < state.tuning.max_minions && roll < 0.2 ->
            {summon, Units.center(target), false}

          "quake" in ready and roll > 0.9 ->
            {"quake", Units.center(target), false}

          "chaos" in ready and roll > 0.85 ->
            {"chaos", Units.center(target), false}

          true ->
            {Enum.find(@bot_attacks, "ember", &(&1 in ready)), Units.center(target), false}
        end

      spell = Catalog.spell(spell_id)

      cond do
        spell.aimless ->
          {{:cast, spell_id, 0, 0}, state}

        spell.place ->
          {px, py} = point

          {x, y} =
            if spell.sky,
              do: {Float.round(px * 1.0, 1), Float.round(py * 1.0, 1)},
              else: within_place_range(me, point, state.tuning.place_range)

          {{:place, spell_id, x, y}, state}

        true ->
          aim_and_cast(state, me, spell, spell_id, point, near_ok)
      end
    end
  end

  defp aim_and_cast(state, me, spell, spell_id, point, near_ok) do
    {angle, power, _} =
      bot_aim(state, Units.caster_origin(state, me.id), me.id, point, spell, near_ok: near_ok)

    {jitter_a, rng} = :rand.normal_s(state.rng)
    {jitter_p, rng} = :rand.normal_s(rng)
    angle = clamp(angle + jitter_a * 1.5, -180, 360)
    power = clamp(power + jitter_p * 2.5, 5, 100)
    {{:cast, spell_id, angle, power}, %{state | rng: rng}}
  end

  # Pulls a point back toward the bot until it is inside the placement range,
  # measured from the same spot the engine's range check uses.
  defp within_place_range(me, {x, y}, range) do
    {ox, oy} = {me.x + 0.5, me.y - 1.0}
    distance = :math.sqrt((x - ox) ** 2 + (y - oy) ** 2)
    k = min(1.0, (range - 2) / max(distance, 0.001))
    {Float.round(ox + (x - ox) * k, 1), Float.round(oy + (y - oy) * k, 1)}
  end

  defp bot_enemies(state, me) do
    state.units
    |> Map.values()
    |> Enum.filter(&(&1.kind == :wizard and Units.alive_unit?(&1) and &1.id != me.id))
  end

  defp unit_distance(a, b), do: abs(a.x - b.x) + abs(a.y - b.y)

  # A cheap ballistic search that ignores terrain proposes shots; the real flight
  # simulation checks the best few. Returns {angle, power, expected miss}.
  defp bot_aim(state, {ox, oy} = origin, caster, {tx, ty}, spell, opts) do
    {angle_step, power_step, keep} =
      if opts[:coarse], do: {8, 10, 3}, else: {4, 5, 6}

    ax = state.wind * state.tuning.wind_accel * spell.wind
    ay = state.tuning.gravity * spell.gravity

    for(
      angle <- -60..240//angle_step,
      power <- 20..100//power_step,
      do:
        {angle, power,
         closest_approach(
           origin,
           Physics.launch(spell, angle, power),
           {ax, ay},
           {tx, ty},
           0,
           1.0e9
         )}
    )
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.take(keep)
    |> Enum.map(fn {angle, power, _} ->
      {_path, {kind, {x, y}}} =
        Physics.fly(state, origin, Physics.launch(spell, angle, power), spell, caster)

      miss = :math.sqrt((x - tx) ** 2 + (y - ty) ** 2)

      self_risk =
        if not Keyword.get(opts, :near_ok, false) and
             :math.sqrt((x - ox) ** 2 + (y - oy) ** 2) < spell.radius + 4,
           do: 50,
           else: 0

      lost = if kind in [:water, :out, :lost], do: 20, else: 0
      {angle, power, miss + self_risk + lost}
    end)
    |> Enum.min_by(&elem(&1, 2))
  end

  defp closest_approach(_pos, _v, _a, _target, 200, best), do: best

  defp closest_approach({x, y}, {vx, vy}, {ax, ay}, {tx, ty}, n, best) do
    vx = vx + ax * @dt
    vy = vy + ay * @dt
    x = x + vx * @dt
    y = y + vy * @dt
    best = min(best, (x - tx) ** 2 + (y - ty) ** 2)

    if y > @height or x < -20 or x > @width + 20,
      do: best,
      else: closest_approach({x, y}, {vx, vy}, {ax, ay}, {tx, ty}, n + 1, best)
  end
end
