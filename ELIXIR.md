# Flamingo: Elixir LiveView Rewrite Plan

## Overview

Rewrite the Flamingo drawing/guessing game from Go + SolidJS to Elixir + Phoenix LiveView. The game is a Skribbl.io clone: players join a room, take turns drawing while others guess the word, earn points, and see a showcase of drawings at the end.

## Current Architecture (Go + SolidJS)

- **Backend**: Single Go binary serving static files + WebSocket game server
- **Frontend**: SolidJS SPA with Vite, Tailwind v4, Kobalte UI primitives
- **State**: In-memory, single-goroutine event loop per room with channel-based message passing
- **Protocol**: JSON WebSocket messages with a phase-change-ack synchronisation barrier
- **Canvas**: Raw `ImageData` pixel manipulation (Line Segment SDF for strokes, flood fill)
- **No database, no reconnection, no room cleanup**

## Target Architecture (Elixir + Phoenix LiveView)

### Process Architecture

```
Application Supervisor
├── (Flamingo.Repo — not needed initially, add later for persistent replays)
├── Phoenix.PubSub (Flamingo.PubSub)
├── Flamingo.GameRegistry (Registry, keys: :unique, name lookup by room_id)
├── Flamingo.GameSupervisor (DynamicSupervisor)
│   ├── Flamingo.GameServer (GenServer, one per room)
│   ├── Flamingo.GameServer ...
│   └── ...
└── FlamingoWeb.Endpoint
    └── LiveView sockets
        └── FlamingoWeb.GameLive (one per player connection)
```

### Core Components

#### 1. `Flamingo.GameServer` (GenServer)

One per room. Owns all game state. Identified by room_id in the Registry.

**State shape:**
```elixir
%{
  room_id: String.t(),
  phase: :lobby | :setup | :in_progress | :score_display | :game_over,
  players: %{socket_id => %Player{id, name, score, connected}},
  player_order: [socket_id],     # ordered list for turn rotation
  host_id: socket_id,
  current_drawer_idx: integer(),
  word: String.t() | nil,
  word_choices: [String.t()],
  correct_guess_times: %{socket_id => DateTime.t()},
  turn_start_time: DateTime.t() | nil,
  round_duration: integer(),     # seconds
  total_rounds: integer(),
  current_round: integer(),      # 0-indexed
  drawn_this_round: MapSet.t(),
  current_drawing: [draw_event], # events for current turn
  drawing_histories: [%{player_id, player_name, events}],
  hint_timers: [reference()],    # timer refs for cancellation
  phase_timer: reference() | nil,
  round_scores: map() | nil      # stashed between score_display and application
}
```

**Key design decisions:**
- No ack barrier needed. The Go version uses `phaseChangeAck` because WebSocket messages can arrive out of order or before the client is ready. LiveView handles this naturally — `push_event` calls are queued and delivered in order, and the server controls what the client renders.
- Timers via `Process.send_after/3`. Each timer returns a reference stored in state. On phase change, cancel any active timers with `Process.cancel_timer/1`.
- Player disconnect/reconnect tracked via `connected` flag rather than removing from state immediately. This enables reconnection (improvement over Go version).

**Room cleanup:** Schedule a `Process.send_after` on game over or when all players disconnect. After 5 minutes of inactivity, the GenServer terminates itself. The DynamicSupervisor handles cleanup automatically.

#### 2. `FlamingoWeb.GameLive` (LiveView)

One LiveView process per player. Subscribes to PubSub topic `game:{room_id}`.

**Lifecycle:**
1. `mount/3` — look up or create GameServer, register player, subscribe to PubSub
2. `handle_info/2` — receive broadcasts from GameServer via PubSub
3. `handle_event/3` — receive UI events from the browser (guesses, chat, start game, word selection)
4. `terminate/2` — notify GameServer of disconnect

**PubSub topics:**
- `game:{room_id}` — game-wide broadcasts (phase changes, player updates, chat, correct guesses)
- Direct `send/2` to specific LiveView pids for player-specific messages (word choices for drawer, word reveal on correct guess)

**How the GameServer reaches LiveViews:**
- GameServer stores `%{socket_id => %Player{pid: pid}}` where `pid` is the LiveView process
- For broadcasts: `Phoenix.PubSub.broadcast(Flamingo.PubSub, "game:#{room_id}", message)`
- For targeted messages: `send(player.pid, message)`
- LiveView processes handle both via `handle_info/2`

#### 3. Canvas Hook (`DrawingCanvas`)

LiveView cannot directly manipulate `<canvas>`. We need a JavaScript hook.

**Hook responsibilities:**
- Capture pointer events (down, move, up, leave, enter)
- Render strokes locally for the drawer (zero latency)
- Push draw events to server via `this.pushEvent("draw_event", payload)`
- Receive remote draw events via `this.handleEvent("draw_event", callback)`
- Handle undo/clear locally and push to server
- On reconnect: receive full drawing history and replay

**Event flow (drawer):**
```
Pointer event → JS hook renders locally → pushEvent("draw_event") → GameServer
  → GameServer appends to current_drawing
  → GameServer broadcasts via PubSub
  → Other LiveViews receive in handle_info
  → Other LiveViews push_event("draw_event") to their hooks
  → Viewer hooks render the stroke
```

**Event flow (viewer reconnect):**
```
LiveView mounts → GameServer sends current_drawing list → LiveView push_event("replay_drawing", events)
  → Hook replays all events to reconstruct canvas
```

**Draw event structure (same as current):**
```javascript
{eventType: "start"|"draw"|"end"|"fill"|"clear"|"undo", x, y, color, lineWidth}
```

**Canvas rendering:** Port the existing `canvas.ts` (Line Segment SDF `drawBetween`, flood `fill`) directly. This is pure JS that operates on `ImageData` — it doesn't depend on SolidJS.

**Undo mechanism:**
- Drawer's hook maintains local `drawEventsStack`
- On undo: find last `fill`/`start`/`clear`, splice from there, replay remaining events
- Push an `undo` event to server
- Server removes the same range from `current_drawing` and broadcasts `undo` to viewers
- Viewers replay from their own stacks

**Why not channel the canvas through LiveView diffs?** Draw events are high-frequency (every pointer move). LiveView's diff mechanism would add unnecessary overhead. `pushEvent`/`handleEvent` bypasses the diff system and communicates directly with the JS hook, which is exactly what we want.

#### 4. Drawing Replay Hook (`DrawingReplay`)

For the game end showcase. Receives a complete event list and renders on a scaled canvas with a slider for scrubbing. Same rendering code as `DrawingCanvas` but read-only.

### Phase State Machine

```
:lobby
  ├─ start_game (from host) ──→ :setup
  └─ (< 2 players while active) ──→ :game_over

:setup
  ├─ select_word (from drawer) ──→ :in_progress
  └─ timeout (10s) ──→ :in_progress (random word chosen)

:in_progress
  ├─ all_guessed ──→ :score_display (after 1s delay)
  ├─ timeout (round_duration) ──→ :score_display (after 1s delay)
  └─ drawer disconnects ──→ :score_display

:score_display
  └─ timeout (5s) ──→ apply scores, save drawing
      ├─ more turns this round ──→ :setup
      ├─ more rounds ──→ :setup (increment round)
      └─ all rounds done ──→ :game_over

:game_over
  └─ timeout (5min) ──→ GenServer terminates
```

No ack barrier phase. LiveView's server-rendered HTML means the client always shows what the server tells it to show. Phase transitions are atomic from the client's perspective.

### Routing

```elixir
# router.ex
live "/", HomeLive          # create/join room
live "/game/:room_id", GameLive  # the game
```

No SPA-style client routing. Phoenix handles it. Room existence check happens in `GameLive.mount/3` — if no GameServer exists for the room_id, redirect to home with a flash message.

### Room Creation

```elixir
# HomeLive
def handle_event("create_room", _params, socket) do
  room_id = Flamingo.RoomId.generate()  # adjective-animal slug
  {:ok, _pid} = DynamicSupervisor.start_child(Flamingo.GameSupervisor, {Flamingo.GameServer, room_id: room_id})
  {:noreply, push_navigate(socket, to: ~p"/game/#{room_id}")}
end
```

### Player Registration Flow

```elixir
# GameLive.mount/3
def mount(%{"room_id" => room_id}, _session, socket) do
  # On first mount, show name entry form
  # After name submission:
  case Flamingo.GameServer.join(room_id, self(), player_name) do
    {:ok, game_state} ->
      Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
      {:ok, assign(socket, game_state_to_assigns(game_state))}
    {:error, :not_found} ->
      {:ok, push_navigate(socket, to: ~p"/")}
  end
end
```

On LiveView disconnect (`terminate/2`), notify GameServer. GameServer marks player as `connected: false` and starts a 30-second reconnection window. If the LiveView reconnects within that window (detected by matching player name + session), restore the player's state.

### Hint System

```elixir
# In GameServer, when transitioning to :in_progress
defp schedule_hints(state) do
  ref1 = Process.send_after(self(), {:hint, 1}, :timer.seconds(29))
  ref2 = Process.send_after(self(), {:hint, 2}, :timer.seconds(39))
  %{state | hint_timers: [ref1, ref2]}
end
```

Hint letter selection uses deterministic hashing (FNV of the word, same as Go version) so hints are consistent.

### Scoring

Pure functions, direct port from Go:

```elixir
defmodule Flamingo.Scoring do
  @base_score 300
  @first_bonus 100
  @min_score 50
  @min_gap 25

  def calculate_guesser_scores(correct_guess_times, round_duration) do
    # Sort by time, first guesser gets 400, rest decay by time ratio
    # Floor at previous_score - 25, absolute floor at 50
  end

  def calculate_drawer_score(num_guessers, total_players) do
    # 0 guessers: -100, 1: +100, all: +350, linear interpolation between
  end
end
```

### Word List

Embed at compile time:

```elixir
defmodule Flamingo.Words do
  @words File.read!("priv/words/default.txt") |> String.split("\n", trim: true)
  def random_choices(n \\ 3), do: Enum.take_random(@words, n)
end
```

Copy `backend/words/default.txt` to `priv/words/default.txt`.

---

## UI Architecture

### Templates & Components

All screens rendered as LiveView templates with Phoenix function components. Tailwind CSS for styling — port the neobrutalism aesthetic from https://www.neobrutalism.dev/styling.

**Layout structure (game.html.heex):**
```heex
<div class="relative min-h-screen">
  <.background phase={@phase} />

  <%= case @phase do %>
    <% :lobby -> %> <.lobby_screen {assigns} />
    <% :setup -> %> <.word_choice_screen {assigns} />
    <% :in_progress -> %> <.guessing_screen {assigns} />
    <% :score_display -> %> <.score_display_screen {assigns} />
    <% :game_over -> %> <.game_end_screen {assigns} />
  <% end %>
</div>
```

**Component mapping (SolidJS → Phoenix):**

| SolidJS Component | Phoenix Equivalent |
|---|---|
| `RoomConnection` | `HomeLive` (separate LiveView) |
| `LobbyScreen` | `lobby_screen/1` function component |
| `WordChoiceScreen` | `word_choice_screen/1` + modal component |
| `GuessingScreen` | `guessing_screen/1` (the main 3-panel layout) |
| `ScoreDisplayScreen` | `score_display_screen/1` + overlay |
| `GameEndScreen` | `game_end_screen/1` |
| `Whiteboard` | `<canvas>` with `DrawingCanvas` hook |
| `PlayerList` | `player_list/1` function component |
| `ChatBox` | `chat_box/1` function component |
| `GuessInput` | `<form phx-submit="guess">` |
| `GameHeader` | `game_header/1` with timer hook |
| `WordDisplay` | `word_display/1` |
| `TimerDisplay` | JS hook for countdown (server sends end timestamp) |
| `DrawingReplay` | `<canvas>` with `DrawingReplay` hook |
| `DrawingCarousel` | `drawing_carousel/1` with prev/next buttons |

### Hooks Summary

| Hook Name | Purpose | Events In (server→client) | Events Out (client→server) |
|---|---|---|---|
| `DrawingCanvas` | Drawing + viewing canvas | `draw_event`, `replay_drawing`, `clear_canvas` | `draw_event` |
| `DrawingReplay` | End-game replay canvas | `load_drawing` | (none) |
| `Timer` | Countdown display | `set_timer` | (none) |
| `SoundManager` | Audio playback | `play_sound`, `start_music`, `stop_music` | (none) |
| `ScrollBottom` | Auto-scroll chat | (triggered by DOM mutation) | (none) |

### Styling — Neobrutalism

The current UI uses neobrutalism styling from https://www.neobrutalism.dev/styling. The visual pattern is:
- `border-2` with a dark border color
- Hard offset box shadows: `4px 4px 0px 0px` in the border color (no blur, no spread)
- `border-radius: 0px` everywhere (sharp corners)
- Active/press state: `translate-x-[4px] translate-y-[4px] shadow-none` (button "sinks" into its shadow)
- Bold, high-contrast colors (pink-200 background, pink-300 primary, dark purple-blue text)

This is almost entirely Tailwind classes + CSS custom properties. The SolidJS version used Kobalte (Radix-like) for **behavioral** concerns (dropdown positioning, slider drag, keyboard nav, toggle state), not for styling.

**In LiveView, we don't need a JS component library.** The interactive components in this game are simple enough:
- **Brush size dropdown** (3 options) → `phx-click` toggle with `phx-click-away` to close. No complex positioning needed.
- **Pen/fill tool toggle** (2 buttons) → two buttons, server tracks which is active, style with conditional classes
- **Round count slider** (lobby) → `<input type="range">` styled with Tailwind
- **Replay scrubber** (game end) → `<input type="range">` inside the `DrawingReplay` hook (purely client-side, no server interaction)
- **Word choice modal** → fixed overlay div, shown/hidden by phase assign
- **Score display overlay** → same pattern

**CSS custom properties to define in `app.css`:**
```css
@theme {
  --color-background: var(--color-pink-200);
  --color-primary: var(--color-pink-300);
  --color-foreground: oklch(0.28 0.09 268);
  --color-border: oklch(0.28 0.09 268);
  --shadow-shadow: 4px 4px 0px 0px oklch(0.28 0.09 268);
}
```

**Static assets to copy:**
- Fonts: `Daydream.ttf`, `abduction2002.ttf` → `priv/static/fonts/`
- Sounds: all 7 audio files → `priv/static/sounds/`
- Word list: `default.txt` → `priv/words/`
- Color palette and brush sizes: hardcoded in the DrawingCanvas hook

**Backgrounds:**
- Grid background (pink-100 with 70px grid lines) — port as CSS class
- Flamingo text background (animated drifting rows of "flamingo" text) — port as CSS keyframes

### Timer Approach

The server sends a target end timestamp. A small JS hook counts down locally:

```javascript
Hooks.Timer = {
  mounted() {
    this.handleEvent("set_timer", ({end_time}) => {
      this.endTime = new Date(end_time)
      this.tick()
    })
  },
  tick() {
    const remaining = Math.max(0, Math.ceil((this.endTime - Date.now()) / 1000))
    this.el.innerText = remaining
    if (remaining > 0) requestAnimationFrame(() => this.tick())
  }
}
```

This avoids server round-trips for timer updates. Same approach as the current SolidJS `useTimer`.

---

## Key Architectural Decisions

### Q1: Do we need the phase-change-ack barrier?

**No.** The Go version needs it because WebSocket messages can arrive before the SolidJS client has re-rendered for the new phase. LiveView doesn't have this problem — the server controls what HTML the client sees. Phase transitions are atomic: the server updates assigns, LiveView diffs the DOM, and any `push_event` calls to hooks are delivered in order.

### Q2: Drawing event throughput — will LiveView keep up?

**Yes, with the right approach.** Draw events must NOT go through LiveView's diff mechanism. Instead we use the `pushEvent`/`handleEvent` hook API, which is a direct JS↔Elixir message channel over the same WebSocket but completely outside the HTML diff/patch cycle.

**How LiveView normally works (the diff path):**
1. Server updates socket assigns (`assign(socket, :foo, "bar")`)
2. LiveView re-renders the `.heex` template
3. Computes a diff against the previous render
4. Sends a compact binary patch to the client
5. Client applies the DOM patch

This is great for UI but disastrous for high-frequency events like drawing — you'd be encoding coordinates into the DOM, diffing them, patching, and parsing them back out in JS.

**How hooks bypass this (the event path):**

```
DRAWER → SERVER:
  JS hook calls this.pushEvent("draw_event", {x: 10, y: 20, ...})
    → arrives at GameLive.handle_event("draw_event", payload, socket)
    → we return {:noreply, socket} with NO assign changes
    → NO template re-render, NO diff computation

SERVER → VIEWERS:
  GameLive calls push_event(socket, "draw_event", payload)
    → sent as a raw JSON message on the WebSocket
    → JS hook's this.handleEvent("draw_event", callback) fires
    → callback draws directly on canvas
    → NO DOM involvement whatsoever
```

The key insight: `push_event/3` and `this.pushEvent()` use the LiveView WebSocket as a raw bidirectional message channel. The data never touches the template, the diff engine, or the DOM. It's as close to a raw WebSocket as you can get while still being managed by LiveView's connection lifecycle (reconnection, heartbeats, etc.).

**Concrete code:**

```elixir
# GameLive — drawer sends a draw event
def handle_event("draw_event", payload, socket) do
  # Forward to GameServer. cast = fire-and-forget, no blocking.
  GenServer.cast(socket.assigns.game_pid, {:draw_event, socket.assigns.player_id, payload})
  # Return socket unchanged. No assigns touched. No re-render.
  {:noreply, socket}
end

# GameLive — receive broadcast from GameServer via PubSub
def handle_info({:draw_event, payload}, socket) do
  # Push directly to the JS hook. No assigns, no template, no diff.
  {:noreply, push_event(socket, "draw_event", payload)}
end
```

```javascript
// DrawingCanvas hook
Hooks.DrawingCanvas = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext("2d")

    // Receive events from server — bypasses DOM entirely
    this.handleEvent("draw_event", (payload) => {
      drawOnCanvas(this.ctx, payload)
    })

    // Receive full replay on reconnect
    this.handleEvent("replay_drawing", ({events}) => {
      clearCanvas(this.ctx)
      events.forEach(e => drawOnCanvas(this.ctx, e))
    })

    // If this is the drawer, capture pointer events and push to server
    if (this.el.dataset.role === "drawer") {
      this.el.addEventListener("pointermove", (e) => {
        const {x, y} = translatePointer(e, this.canvas)
        this.pushEvent("draw_event", {eventType: "draw", x, y, color: this.color, lineWidth: this.size})
      })
    }
  }
}
```

Start with individual events, batch later if measurement shows it's needed.

### Q3: ETS or GenServer for drawing storage?

**GenServer state is sufficient.** Drawings only live for the duration of a game (minutes to an hour). The data is a list of simple maps. There's no concurrent read pattern that would benefit from ETS. The GenServer already serializes all access, and the data dies when the game ends. ETS would add complexity for no benefit.

Drawing histories for the end-game replay are just kept in the GenServer's `drawing_histories` list. They live as long as the game does. Persistent storage is a separate concern for later.

### Q4: Phoenix Presence for player tracking?

**No, overkill.** Presence is designed for distributed systems where you need to track connections across nodes. We're running a single node on Fly.io. The GameServer's player map plus PubSub subscription tracking is sufficient. If we scale to multiple nodes later, we can add Presence then.

### Q5: How to handle reconnection?

**LiveView gives us this almost for free.** When a LiveView socket disconnects, it automatically attempts to reconnect. On reconnect, `mount/3` is called again. The flow:

1. Store `player_session_id` in the LiveView session (a cookie-based token)
2. On mount, check if GameServer has a disconnected player matching this session
3. If yes: restore their state, mark as connected, push current drawing for replay
4. If no: treat as new player

This is a significant improvement over the Go version which has zero reconnection support.

### Q6: Undo/redo — server-authoritative or client-side?

**Hybrid.** The drawer maintains a local event stack for instant undo feedback. On undo:
1. Hook splices its local stack and replays (instant visual feedback)
2. Hook pushes `{eventType: "undo"}` to server
3. Server splices `current_drawing` identically
4. Server broadcasts `undo` to viewer hooks
5. Viewer hooks splice and replay their local stacks

This keeps undo instant for the drawer while maintaining server authority. The server's `current_drawing` is always the source of truth for reconnection and end-game replay.

### Q7: How to serve the clear canvas operation?

**Same as undo but simpler.** Push a `{eventType: "clear"}` event. Server appends it to `current_drawing` and broadcasts. All hooks clear their canvas. On replay, `clear` resets the canvas at that point in the event stream.

### Q8: Sound effects in LiveView?

**JS hook.** Create a `SoundManager` hook attached to a persistent element. Server pushes events like `push_event(socket, "play_sound", %{sound: "correct_guess"})`. The hook pre-loads audio files and plays on demand. Same pattern as the current `sound-manager.ts`.

---

## Build Sequence

### Phase 1: Project Bootstrap
1. `mix phx.new elixir --app flamingo --no-ecto --no-mailer --no-dashboard` (generates into `/elixir`)
   - No Ecto, no database — all state is in-memory
   - No mailer
   - No LiveDashboard in production
2. Add `scripts/worktree_setup.exs` and `scripts/worktree_run_server.exs`
3. Configure `dev.exs` to read `PORT` from env (for Conductor worktree support)
4. Configure Tailwind with neobrutalism theme
5. Copy static assets (fonts, sounds, word list)
6. Set up basic routing (`HomeLive`, `GameLive`)

### Phase 2: Game Server Core
1. `Flamingo.GameServer` GenServer with full state machine
2. `Flamingo.GameSupervisor` DynamicSupervisor
3. `Flamingo.GameRegistry` for room lookup
4. `Flamingo.RoomId` slug generation (port adjective-animal lists)
5. `Flamingo.Words` word list module
6. `Flamingo.Scoring` scoring logic
7. Unit tests for state transitions, scoring, word selection

### Phase 3: Lobby & Room Management
1. `HomeLive` — create room / join room by code
2. `GameLive` mount — join game, show lobby
3. Player list component
4. Host controls (round count, round duration, start button)
5. PubSub integration — live player updates

### Phase 4: Drawing Canvas
1. Port `canvas.ts` rendering code (drawBetween SDF, fill) to the JS hook
2. `DrawingCanvas` hook — pointer event capture, local rendering, event push
3. Server-side draw event storage and PubSub broadcast
4. Viewer-side rendering via hook events
5. Undo and clear support
6. Color palette, brush size, fill tool UI (Tailwind-styled toolbar)

### Phase 5: Guessing & Chat
1. Word selection phase (setup screen with modal for drawer)
2. Guess input and validation
3. Chat system (messages, system messages, correct guess notifications)
4. Word outline display with hint reveals
5. Timer hook and countdown display

### Phase 6: Scoring & Round Flow
1. Score calculation on round end
2. Score display overlay
3. Round progression logic (next drawer, next round, game over)
4. Turn-end transitions with proper cleanup

### Phase 7: Game End & Replay
1. Game over screen with final scoreboard
2. `DrawingReplay` hook — canvas replay with slider scrubbing
3. Drawing carousel with prev/next navigation

### Phase 8: Polish
1. Sound effects hook
2. Reconnection support
3. Background animations (flamingo text, grid)
4. Room cleanup on inactivity
5. Error handling and edge cases

### Phase 9: Deployment
1. Dockerfile for Elixir release
2. Fly.io configuration
3. CI/CD pipeline

---

## Resolved Decisions

1. **Draw event batching:** Send individually. Measure first, batch later if needed.
2. **Canvas size:** Keep 700×500 fixed. Matches the pixel-art aesthetic.
3. **Room capacity:** Cap at 12 players.
4. **Persistent replays:** Out of scope. Replays are in-memory only (GenServer state), shown at game end, lost when the GameServer terminates. Add SQLite later if needed.
5. **Mobile support:** Not in initial scope.
6. **Canvas clear:** Supported — `{eventType: "clear"}` appended to event stream, broadcast to all hooks, acts as a reset point during replay.
7. **Score calculation:** Calculate once at round end, stash in state for display, apply after the 5s score display timer.

---

## Project Structure & Scripts

The Elixir app lives in `/elixir` at the repo root. Scripts follow the chief_wiggum pattern for Conductor worktree compatibility.

### Directory Layout

```
/elixir/                           # Phoenix app root
├── scripts/
│   ├── worktree_setup.exs         # Bootstrap: deps, assets
│   └── worktree_run_server.exs    # Start server on correct port
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs                    # PORT from env, default 4000
│   ├── test.exs
│   └── runtime.exs                # PHX_SERVER, PORT for prod/scripts
├── lib/
│   ├── flamingo/
│   │   ├── application.ex
│   │   ├── game_server.ex
│   │   ├── game_supervisor.ex
│   │   ├── game_state.ex
│   │   ├── room_id.ex
│   │   ├── scoring.ex
│   │   └── words.ex
│   └── flamingo_web/
│       ├── router.ex
│       ├── endpoint.ex
│       ├── live/
│       │   ├── home_live.ex
│       │   ├── home_live.html.heex
│       │   ├── game_live.ex
│       │   └── game_live.html.heex
│       └── components/
│           ├── layouts.ex
│           ├── core_components.ex
│           ├── game_components.ex
│           └── backgrounds.ex
├── assets/
│   ├── js/
│   │   ├── app.js
│   │   └── hooks/
│   │       ├── drawing_canvas.js
│   │       ├── drawing_replay.js
│   │       ├── timer.js
│   │       ├── sound_manager.js
│   │       └── scroll_bottom.js
│   └── css/
│       └── app.css
├── priv/
│   ├── static/
│   │   ├── fonts/
│   │   ├── sounds/
│   │   └── images/
│   └── words/
│       └── default.txt
└── test/
```

### Setup Script (`scripts/worktree_setup.exs`)

Follows chief_wiggum pattern. Run from the `/elixir` directory:

```
cd elixir && elixir scripts/worktree_setup.exs
```

Steps:
1. `mix deps.get`
2. `mix assets.setup` (install tailwind + esbuild binaries)

No database, no npm (Phoenix bundles its own JS build pipeline via esbuild).

### Run Script (`scripts/worktree_run_server.exs`)

Reads `CONDUCTOR_PORT` env var. Fails early if not set.

```
cd elixir && elixir scripts/worktree_run_server.exs
```

The script sets `PORT=$CONDUCTOR_PORT` and `PHX_SERVER=true`, then runs `mix run --no-halt`.

### Dev Config (`config/dev.exs`)

```elixir
config :flamingo, FlamingoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-key-not-for-production",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:flamingo, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:flamingo, ~w(--watch)]}
  ]
```

### Runtime Config (`config/runtime.exs`)

```elixir
if System.get_env("PHX_SERVER") do
  config :flamingo, FlamingoWeb.Endpoint, server: true
end
```

This is what makes `worktree_run_server.exs` work — the script sets `PHX_SERVER=true` and `PORT=<N>`, and the Phoenix config reads both.
