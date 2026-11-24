defmodule Flamingo.GameModes.Spellslingers.Units do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Crates, Physics, Terrain, Timeline}

  def damage(state, id, amount, source) do
    case state.units[id] do
      nil ->
        state

      unit ->
        amount = round(amount * state.tuning.damage_pct / 100)
        dealt = min(amount, unit.hp)
        state = put_unit(state, %{unit | hp: unit.hp - dealt})

        if source && source != unit.owner && Map.has_key?(state.damage_dealt, source),
          do: %{state | damage_dealt: Map.update!(state.damage_dealt, source, &(&1 + dealt))},
          else: state
    end
  end

  def place_wizards(state) do
    count = length(state.turn_order)
    spots = standable_spots(state, 3)

    {state, _} =
      state.turn_order
      |> Enum.with_index()
      |> Enum.reduce({state, []}, fn {id, index}, {state, taken} ->
        target = @width / 2 + spawn_band(count) * ((index + 0.5) / count - 0.5)

        apart = Enum.filter(spots, fn {x, _} -> Enum.all?(taken, &(abs(&1 - x) >= 14)) end)
        candidates = if apart == [], do: spots, else: apart

        {x, y} =
          Enum.min_by(candidates, fn {x, _} -> abs(x - target) end, fn -> {round(target), 10} end)

        wizard = %{
          id: id,
          kind: :wizard,
          owner: id,
          x: x,
          y: y,
          hp: @wizard_hp,
          max_hp: @wizard_hp,
          dead: false,
          # Turns left on a broomstick; a floating wizard hovers wherever it is.
          float: 0
        }

        {put_unit(state, wizard), [x | taken]}
      end)

    state
  end

  # Wizards start within reach of each other however wide the world is.
  defp spawn_band(count), do: min(@width - 36, 55 * (count + 1))

  def standable_spots(state, height) do
    for x <- 4..(@width - 5),
        y <- height..(state.water_level - 3),
        Terrain.solid?(state.terrain, x, y + 1),
        Enum.all?(0..(height - 1), &(not Terrain.solid?(state.terrain, x, y - &1))),
        do: {x, y}
  end

  def put_unit(state, unit), do: %{state | units: Map.put(state.units, unit.id, unit)}

  @doc """
  Fills the circles with rock without burying any living unit, then lifts
  anything left inside rock back onto the surface.
  """
  def raise_ground(state, circles) do
    occupied =
      for {_, u} <- state.units,
          alive_unit?(u),
          dy <- 0..(unit_height(u) - 1),
          into: MapSet.new(),
          do: {u.x, u.y - dy}

    state |> Terrain.fill(circles, occupied) |> unbury_all()
  end

  def caster_origin(state, actor) do
    caster = state.units[actor]
    {caster.x + 0.5, caster.y - 2.0}
  end

  def unit_height(%{kind: :wizard}), do: 3
  def unit_height(%{kind: :crate}), do: 1
  def unit_height(_), do: 2

  # Shots connect with everything drawn. A flamingo is drawn about 8 cells tall: thin
  # legs, a round body, then the neck and head. Each part is {half width, bottom, top}
  # in cells above the feet, around the column's middle. The server never knows which
  # way a flamingo faces, so the head reaches both ways.
  @flamingo_parts [{0.9, -0.2, 2.6}, {1.7, 2.6, 5.2}, {1.3, 5.2, 8.1}]

  def hit_parts(%{kind: :wizard}), do: @flamingo_parts
  def hit_parts(unit), do: [{1.6, -0.2, unit_height(unit) + 0.4}]

  @doc "How far the point is from the unit as drawn, or 0 when it is on the unit."
  def distance_to(unit, {x, y}) do
    dx = abs(x - unit.x - 0.5)
    up = unit.y + 1 - y

    unit
    |> hit_parts()
    |> Enum.map(fn {half, bottom, top} ->
      ex = max(dx - half, 0)
      ey = Enum.max([bottom - up, up - top, 0])
      :math.sqrt(ex * ex + ey * ey)
    end)
    |> Enum.min()
  end

  # The middle of the unit as drawn: seekers and AI aim there and blasts push away from it.
  def center(%{kind: :wizard} = unit), do: {unit.x + 0.5, unit.y + 1 - 3.9}
  def center(unit), do: {unit.x + 0.5, unit.y + 1 - unit_height(unit) / 2}

  def blocked?(state, unit, x, y) do
    x < 0 or x >= @width or
      Enum.any?(0..(unit_height(unit) - 1), fn dy -> Terrain.solid?(state.terrain, x, y - dy) end)
  end

  def step(state, unit, dir) do
    x = unit.x + dir

    climb = if Map.get(unit, :float, 0) > 0, do: 6, else: @max_climb

    case Enum.find(0..climb, &(not blocked?(state, unit, x, unit.y - &1))) do
      nil -> {:error, :blocked}
      climb -> {:ok, %{unit | x: x, y: unit.y - climb}}
    end
  end

  # Wizards on a broomstick hover wherever they are.
  def settle(state, unit) do
    if Map.get(unit, :float, 0) > 0, do: {unit, 0}, else: do_settle(state, unit)
  end

  def do_settle(state, unit) do
    fall =
      Enum.reduce_while(0..@height, 0, fn fall, _ ->
        y = unit.y + fall

        if y + 1 >= @height or y >= state.water_level or
             Terrain.solid?(state.terrain, unit.x, y + 1),
           do: {:halt, fall},
           else: {:cont, fall + 1}
      end)

    {%{unit | y: min(unit.y + fall, @height)}, fall}
  end

  @doc """
  Brings everyone down after something moved them or took their ground away. Each unit
  drops to the ground from where its own movement ended, given in `flights` as
  id => {the step it ended, the row it took off from}, or else from step `start`. Then,
  in the order it happens, each lands (hurt by how far it ended up below where it took
  off), picks up any crate there, and is knocked out if that finished it or it is in
  the sea. Units a hit has already left with no health are knocked out where that hit
  struck them, and only their body falls.
  """
  def come_down(state, start, flights \\ %{}) do
    state = state |> unbury_all() |> defeat_struck(start)

    crates =
      state.crates
      |> Enum.map(&elem(settle(state, &1), 0))
      |> Enum.reject(&(&1.y >= state.water_level))

    state = %{state | crates: crates}

    state.units
    |> Map.values()
    |> Enum.reject(&(&1.dead and not Map.has_key?(struck_at(state), &1.id)))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce({state, []}, fn unit, {state, arrivals} ->
      {from, top} = Map.get(flights, unit.id, {start, unit.y})
      {settled, fall} = settle(state, unit)

      # A step or two down is walking down a slope, not a drop.
      dropped? = fall > @max_climb or (fall > 0 and Map.has_key?(flights, unit.id))

      {state, at} =
        if dropped? do
          path = Physics.fall(state, {unit.x, unit.y}, settled.y)
          {Timeline.move(state, unit.id, "fall", from, path), from + length(path) - 1}
        else
          {state, from}
        end

      moved? = dropped? or Map.has_key?(flights, unit.id)
      {state, [{at, unit.id, settled, moved?, settled.y - top} | arrivals]}
    end)
    |> then(fn {state, arrivals} ->
      arrivals
      |> Enum.sort_by(fn {at, id, _, _, _} -> {at, id} end)
      |> Enum.reduce(state, fn {at, id, settled, moved?, drop}, state ->
        state =
          state |> Timeline.at(at) |> put_unit(%{state.units[id] | x: settled.x, y: settled.y})

        cond do
          state.units[id].dead ->
            state

          # Walking down a slope only lands when it is far enough to hurt.
          (moved? or drop > state.tuning.fall_safe) and settled.y < state.water_level ->
            state |> land(id, drop) |> Crates.collect_crates([id]) |> resolve_death(id)

          true ->
            state |> Crates.collect_crates([id]) |> resolve_death(id)
        end
      end)
    end)
  end

  # Knocks out every wizard left with no health, at the step the hit that did it struck
  # (or `start`), before anyone falls.
  defp defeat_struck(state, start) do
    state.units
    |> Map.values()
    |> Enum.filter(&(not &1.dead and &1.hp <= 0))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(state, fn unit, state ->
      at = Map.get(struck_at(state), unit.id, start)
      clock = state.clock
      state |> Timeline.at(at) |> kill(unit, :defeated) |> Map.put(:clock, clock)
    end)
  end

  # The step of each unit's latest hit in the timeline being recorded.
  defp struck_at(%{clock: nil}), do: %{}

  defp struck_at(state) do
    state.timeline.events
    |> Enum.reverse()
    |> Enum.filter(&(&1.kind == "hit" and &1[:id]))
    |> Map.new(&{&1.id, &1.at})
  end

  def unbury_all(state) do
    state.units
    |> Map.values()
    # One in the sea is going under, not lifted onto the nearest cliff.
    |> Enum.filter(&(alive_unit?(&1) and &1.y < state.water_level))
    |> Enum.reduce(state, fn unit, state ->
      lifted =
        Enum.find_value(0..30, fn dy ->
          if not blocked?(state, unit, unit.x, unit.y - dy), do: %{unit | y: unit.y - dy}
        end)

      put_unit(state, lifted || unit)
    end)
  end

  def free_spot(state, x, y, unit) do
    x = clamp(x, 0, @width - 1)
    y = clamp(y, unit_height(unit), @height - 1)

    Enum.find_value(0..40, :error, fn dy ->
      if not blocked?(state, unit, x, y - dy) and y - dy >= unit_height(unit) - 1,
        do: {:ok, %{unit | x: x, y: y - dy}}
    end)
  end

  # Touching down: a drop of more than the safe height hurts, a point for each cell past
  # it, and the chronicle says so, since nothing else explains the hit.
  defp land(state, id, drop) do
    unit = state.units[id]
    safe = state.tuning.fall_safe
    state = if drop > safe, do: damage(state, id, drop - safe, nil), else: state
    lost = unit.hp - state.units[id].hp

    state =
      if lost > 0,
        do: log(state, "#{player_name(state, id)} falls hard and loses #{lost} HP."),
        else: state

    Timeline.event(state, %{kind: "land", id: id, hp: state.units[id].hp})
  end

  defp resolve_death(state, id) do
    unit = state.units[id]

    cond do
      unit.dead -> state
      unit.y >= state.water_level -> state |> put_unit(%{unit | hp: 0}) |> kill(unit, :sea)
      unit.hp <= 0 -> kill(state, unit, :defeated)
      true -> state
    end
  end

  defp kill(state, %{kind: :wizard} = unit, how) do
    words = if how == :sea, do: "sinks beneath the waves", else: "is defeated"

    state
    |> put_unit(%{unit | hp: 0, dead: true, y: min(unit.y, @height - 1)})
    |> Map.update!(:eliminated, &[unit.id | &1])
    |> log("#{player_name(state, unit.id)} #{words}!")
    |> Timeline.event(%{kind: "ko", id: unit.id, hp: 0, sea: how == :sea})
  end

  def alive?(state, id), do: alive_unit?(state.units[id])
  def alive_unit?(nil), do: false
  def alive_unit?(unit), do: not unit.dead and unit.hp > 0

  def player_name(state, id) do
    case state.players[id] do
      %{name: name} -> name
      _ -> "Someone"
    end
  end

  @doc """
  Adds a line to the chronicle. A line logged while a timeline is recorded belongs to
  the step it reached, so clients show it as the animation gets there.
  """
  def log(state, message) do
    n = state.log_count + 1
    timeline = if state.clock, do: state.timeline_count
    line = %{n: n, text: message, timeline: timeline, at: state.clock}
    %{state | log: Enum.take([line | state.log], 10), log_count: n}
  end
end
