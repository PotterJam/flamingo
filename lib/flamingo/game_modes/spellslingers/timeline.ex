defmodule Flamingo.GameModes.Spellslingers.Timeline do
  @moduledoc """
  What clients play for one action, in order: a cast, a step or jump that drops, the
  end of a turn. The server resolves the action at once but records when each part of
  it happens, so every client and the HUD show it as the animation reaches it, and the
  server waits `duration_ms` before anything follows (the retreat, the next turn, the
  results).

  Time is counted in steps of the simulation (`@dt`), from 0 when the action's first
  movement starts. A timeline holds:

    * `segments`: spell flights, each from step `start` along its `path`.
    * `moves`: units moving along a path from step `start`: `"knock"` (thrown by a
      blast), `"jump"` or `"fall"` (a drop to the ground, at the flamingo's own
      fluttering speed).
    * `events`, soonest first, each at step `at` and `ms` after the timeline starts:
      `"hit"` (struck by a spell), `"land"` (touched down; `hp` includes any fall
      damage), `"ko"` (`sea` when it sank), `"crate"` (picked up by `id`, or blown
      away when `id` is nil), and `"tide"` (the sea rose to `level`).

  Every event that changes a unit carries the `hp` it leaves. Chronicle lines logged
  while a timeline is open are stamped with its id and the step they belong to.

  A knockout slows the timeline down for a moment where the knockbacks start
  (`slow_at`), and the Hallowed Orb's impact holds still for a beat (`beat`); `ms/2`
  turns steps into milliseconds with both, the way clients play them.
  """

  use Flamingo.GameModes.Spellslingers.Rules

  @step_ms @dt * 1000 / @playback_speed
  # A knockout's knockbacks open at 0.35 speed for @ko_slow_ms, then ease back to full
  # speed over the next @ko_slow_ms.
  @ko_slow_ms 250
  @beat_ms 140

  def step_ms, do: @step_ms

  @doc "Starts recording an action. `attrs` may set `caster_id`, `spell`, `grand`."
  def open(state, attrs \\ []) do
    id = state.timeline_count + 1

    timeline =
      Map.merge(
        %{
          id: id,
          caster_id: nil,
          spell: nil,
          grand: false,
          shake: false,
          segments: [],
          moves: [],
          events: [],
          auras: [],
          flight_steps: 0,
          slow_at: nil,
          beat: nil,
          lead_ms: 0,
          duration_ms: 0
        },
        Map.new(attrs)
      )

    %{state | timeline_count: id, timeline: timeline, clock: 0, previous: state.timeline}
  end

  def open?(state), do: state.clock != nil

  @doc "Moves the recording on (or back) to step `at`."
  def at(state, at), do: if(open?(state), do: %{state | clock: at}, else: state)

  @doc "Records an event at the current step, when a timeline is open."
  def event(state, event) do
    if open?(state),
      do: update_in(state.timeline.events, &[Map.put(event, :at, state.clock) | &1]),
      else: state
  end

  def move(state, id, kind, start, path) do
    if open?(state) do
      move = %{id: id, kind: kind, start: start, path: Enum.map(path, &round_point/1)}
      update_in(state.timeline.moves, &[move | &1])
    else
      state
    end
  end

  @doc """
  Ends the recording: orders the events, works out when each happens and how long the
  whole thing takes. An action with nothing to show records no timeline at all.
  """
  def close(state) do
    t = state.timeline

    if t.segments == [] and t.moves == [] and t.events == [] and t.auras == [] and
         t.spell == nil do
      log = Enum.map(state.log, &if(&1.timeline == t.id, do: %{&1 | timeline: nil}, else: &1))

      %{
        state
        | timeline: state.previous,
          timeline_count: t.id - 1,
          clock: nil,
          previous: nil,
          log: log
      }
    else
      do_close(state, t)
    end
  end

  defp do_close(state, t) do
    events = t.events |> Enum.reverse() |> Enum.sort_by(& &1.at)
    moves = Enum.reverse(t.moves)
    kos = Enum.filter(events, &(&1.kind == "ko"))
    beat = holy_beat(t.segments)
    slow_at = if kos != [] and moves != [], do: t.flight_steps

    t = %{t | events: events, moves: moves, beat: beat, slow_at: slow_at}
    t = %{t | lead_ms: if(t.grand, do: @grand_intro_ms, else: 0)}

    steps =
      Enum.max(
        [t.flight_steps] ++
          Enum.map(t.segments, &(&1.start + length(&1.path) - 1)) ++
          Enum.map(moves, &(&1.start + length(&1.path) - 1)) ++ Enum.map(events, & &1.at)
      )

    events = Enum.map(events, &Map.put(&1, :ms, ms(t, &1.at)))
    tail = if(t.shake, do: 700, else: 300)
    last_ko = kos |> Enum.map(&ms(t, &1.at)) |> Enum.max(fn -> nil end)
    # A knockout's banner holds a moment before anything follows.
    duration = max(ms(t, steps) + tail, if(last_ko, do: last_ko + 1000, else: 0))

    log =
      Enum.map(state.log, fn line ->
        if line.timeline == t.id, do: Map.put(line, :ms, ms(t, line.at)), else: line
      end)

    %{
      state
      | timeline: %{t | events: events, duration_ms: duration},
        clock: nil,
        previous: nil,
        log: log
    }
  end

  defp holy_beat(segments) do
    Enum.find_value(segments, fn s ->
      if s.spell == "holyorb" and s.hit and s.radius > 0,
        do: %{at: s.start + length(s.path) - 1, ms: @beat_ms}
    end)
  end

  @doc "When step `at` of the timeline plays, in ms after it starts."
  def ms(t, at) do
    beat = if t.beat && at > t.beat.at, do: t.beat.ms, else: 0
    linear = t.lead_ms + at * @step_ms + beat

    if t.slow_at && at > t.slow_at do
      t.lead_ms + t.slow_at * @step_ms + beat + unwarp((at - t.slow_at) * @step_ms)
    else
      linear
    end
    |> round()
  end

  # How long the slowed-down stretch takes to play `played` ms of the simulation.
  defp unwarp(played) do
    k = @ko_slow_ms

    cond do
      played <= 0.35 * k ->
        played / 0.35

      played <= 1.025 * k ->
        a = 0.65 / (2 * k)
        c = 0.35 * k - played
        k + (-0.35 + :math.sqrt(0.35 * 0.35 - 4 * a * c)) / (2 * a)

      true ->
        played + 0.975 * k
    end
  end

  defp round_point({x, y}), do: [Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)]
  defp round_point([x, y]), do: round_point({x, y})
end
