# Flamingo: Go → Elixir Migration Plan

## Overview

This document outlines a phased approach to migrate the Flamingo backend from Go to Elixir, enabling incremental testing and validation at each stage. The strategy leverages Elixir's strengths in concurrent, distributed systems while maintaining the existing game logic and WebSocket architecture.

**Key Philosophy:** Migrate in vertical slices by game phase, starting with the lobby where manual testing is easiest, progressively adding complexity as we move through the game flow.

---

## Phase 0: Foundation & Tooling Setup

### Goals
- Set up a working Elixir Phoenix project with WebSocket support
- Establish the project structure and naming conventions
- Get a minimal "hello world" WebSocket endpoint working
- Document build, run, and test processes

### Deliverables
- [ ] New Phoenix project with `mix new` or generator
- [ ] WebSocket endpoint configured with Phoenix.Socket
- [ ] Basic HTTP handler for room creation
- [ ] Development environment setup (environment config, hot reload)
- [ ] Updated documentation with how to run both backends

### Key Decisions
1. **Framework:** Phoenix (blessed by Elixir community, first-class WebSocket support)
2. **Architecture:** Leverage OTP - rooms as GenServer processes, games as separate processes
3. **Message Protocol:** Maintain existing JSON message format for frontend compatibility
4. **Dependencies:**
   - `phoenix` - web framework
   - `phoenix_live_socket` or raw `:socket` for WebSocket
   - `jason` - JSON encoding/decoding
   - `ecto` - if we add persistence later
   - `uuid` - player ID generation

### Testing Strategy
- Unit tests for helper functions
- Integration tests for WebSocket connections
- Manual testing via existing frontend (which talks JSON)

---

## Phase 1: Room Management & Lobby (WaitingInLobby)

### Goals
- Create a room system that mirrors the current Go implementation
- Implement WebSocket upgrade endpoint with player registration
- Support the WaitingInLobby phase where players join and the host starts the game
- Enable manual testing by connecting multiple players to a room via WebSocket

### Architecture

#### Room Process (GenServer)
```elixir
# lib/flamingo/room.ex
defmodule Flamingo.Room do
  use GenServer

  # State: %{
  #   id: string,
  #   players: %{player_id => player_struct},
  #   game: nil | game_pid,
  #   broadcast_fn: callback for sending messages
  # }

  def start_link(room_id), do: GenServer.start_link(__MODULE__, room_id)
  def register_player(room_pid, player), do: GenServer.call(room_pid, {:register, player})
  def unregister_player(room_pid, player_id), do: GenServer.cast(room_pid, {:unregister, player_id})
  def broadcast(room_pid, msg_type, payload), do: GenServer.cast(room_pid, {:broadcast, msg_type, payload})
  def broadcast_to_players(room_pid, msg_type, payload, player_ids), do: ...
end
```

#### Player Connection Handler
```elixir
# lib/flamingo_web/channels/game_channel.ex
defmodule FlamingoDB.GameChannel do
  use Phoenix.Channel

  # Handles connection at /ws/:room_id?player_name=<name>
  def join("game:" <> room_id, params, socket) do
    player_id = UUID.uuid4()
    player_name = params["player_name"] || "Anonymous"

    room_pid = ensure_room_exists(room_id)
    player = %Player{id: player_id, name: player_name, score: 0}

    case Flamingo.Room.register_player(room_pid, player, self()) do
      :ok ->
        {:ok, assign(socket, player_id: player_id, room_pid: room_pid, room_id: room_id)}
      :error ->
        {:error, :room_full}
    end
  end
end
```

#### Room Supervisor
```elixir
# lib/flamingo/room_manager.ex or use DynamicSupervisor
defmodule Flamingo.RoomManager do
  use DynamicSupervisor

  def start_link(init_arg), do: DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  def create_room(room_id) do
    spec = {Flamingo.Room, room_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def get_or_create_room(room_id) do
    case Registry.lookup(Flamingo.RoomRegistry, room_id) do
      [{room_pid, _}] -> room_pid
      [] -> {:ok, room_pid} = create_room(room_id); room_pid
    end
  end
end
```

### Deliverables
- [ ] GenServer-based room management
- [ ] WebSocket channel with connection/disconnection handling
- [ ] Player registration/unregistration in room state
- [ ] Room supervision tree
- [ ] Broadcast mechanism to send messages to connected players
- [ ] `startGame` message handler (transitions to Phase 1 - PhaseChangeAck)
- [ ] Integration tests for room creation and player joining
- [ ] Manual test: Connect 2-3 clients, see player list update, trigger startGame

### Testing Strategy
**Manual Testing Script:**
```bash
# Terminal 1: Start Elixir server
mix phx.server

# Terminals 2-3: Connect via wscat or custom client
wscat -c "ws://localhost:4000/socket/websocket?vsn=2.0" \
  --subprotocol websocket \
  '{"topic":"game:bold-alpaca","event":"phx_join","ref":1,"payload":{"player_name":"Alice"}}'
```

### Key Considerations
1. **Registry:** Use Elixir Registry to track room PIDs by room_id, so lookups are O(1)
2. **Broadcast:** Use `broadcast/2` from Phoenix.Channel or custom broadcast mechanism
3. **Player State:** Keep player info lightweight - just name, id, score
4. **JSON Protocol:** Maintain compatibility with frontend - use `Jason` for encoding/decoding

---

## Phase 2: Phase Management & Acknowledgment (PhaseChangeAck)

### Goals
- Implement the phase FSM with all 8 phase handlers
- Implement the critical PhaseChangeAck synchronization mechanism
- Enable safe phase transitions

### Architecture

#### Game Process (GenServer)
```elixir
# lib/flamingo/game.ex
defmodule Flamingo.Game do
  use GenServer

  # State: %{
  #   phase: atom (:lobby, :setup, :in_progress, :score_display, :finished, :over, :error, :change_ack),
  #   game_state: GameState,
  #   room_id: string,
  #   room_pid: pid,
  #   timers: map of active timers,
  #   phase_handler: module atom for current phase
  # }
end
```

#### Phase Handler Behavior
```elixir
# lib/flamingo/game/phase_handler.ex
defmodule Flamingo.Game.PhaseHandler do
  @callback phase() :: atom
  @callback start_phase(game_state :: map) :: {:ok, game_state :: map} | {:error, term}
  @callback handle_message(game_state :: map, player_id :: string, message :: map) ::
    {:ok, game_state :: map, next_phase :: atom} | {:error, term}
  @callback handle_timeout(game_state :: map) :: {:ok, game_state :: map, next_phase :: atom} | {:error, term}
end
```

#### Concrete Phase Handlers
```elixir
# lib/flamingo/game/phases/waiting_in_lobby.ex
# lib/flamingo/game/phases/phase_change_ack.ex
# lib/flamingo/game/phases/round_setup.ex
# lib/flamingo/game/phases/round_in_progress.ex
# lib/flamingo/game/phases/round_score_display.ex
# lib/flamingo/game/phases/round_finished.ex
# lib/flamingo/game/phases/game_over.ex
```

### Deliverables
- [ ] Game GenServer with phase state management
- [ ] PhaseHandler behavior module
- [ ] All 8 phase handler implementations (initially minimal/stubbed)
- [ ] Phase transition logic with timeout support
- [ ] Broadcast from game state to room
- [ ] Timer management using `Process.send_after/3` and message-based timeouts
- [ ] Integration tests for phase transitions
- [ ] Manual test: Start game → transitions through PhaseChangeAck → can see phase updates

### Key Considerations
1. **State Machine:** Use pattern matching and recursion-free FSM (just states, not stateful processes for each phase)
2. **Timeouts:** Use `Process.send_after/3` to schedule timeout messages to game GenServer
3. **Broadcasts:** Game sends messages to room, room broadcasts to players
4. **Acknowledgment:** Track which players have acknowledged each phase, timeout non-responders

---

## Phase 3: Round Setup & Word Selection (RoundSetup)

### Goals
- Implement word selection and drawer rotation
- Send correct messages to drawer vs. guessers
- Implement timeout logic (randomly pick word if drawer doesn't select)

### Architecture

#### Word Management
```elixir
# lib/flamingo/words.ex
defmodule Flamingo.Words do
  def get_random_words(count \\ 3), do: Enum.take_random(@word_list, count)
  def hash_hint(word, hint_level), do: ...
end
```

#### RoundSetup Handler
```elixir
# lib/flamingo/game/phases/round_setup.ex
defmodule Flamingo.Game.Phases.RoundSetup do
  @behaviour Flamingo.Game.PhaseHandler

  def start_phase(gs) do
    # Pick drawer from gs.players (cycle through)
    # Generate 3 random words
    # Send choices to drawer
    # Send outline to guessers
    # Set 10s timer
    {:ok, updated_gs}
  end

  def handle_message(gs, player_id, %{"type" => "selectRoundWord", "payload" => %{"word" => word}}) do
    # Validate drawer is the one sending
    # Store word in game state
    # Transition to RoundInProgress → PhaseChangeAck
    {:ok, updated_gs, :phase_change_ack}
  end

  def handle_timeout(gs) do
    # No word selected, pick random
    # Transition to RoundInProgress → PhaseChangeAck
    {:ok, updated_gs, :phase_change_ack}
  end
end
```

### Deliverables
- [ ] Word list in Elixir (embedded or loaded from file)
- [ ] RoundSetup phase handler
- [ ] Drawer rotation logic
- [ ] Message differentiation (drawer sees choices, guessers see outline)
- [ ] Timeout-triggered random word selection
- [ ] Integration tests for word selection flow
- [ ] Manual test: Start game, see word choices as drawer, outline as guesser, select word and transition

---

## Phase 4: Active Round & Drawing (RoundInProgress)

### Goals
- Handle draw events, chat, and guess messages
- Implement hint system (30s & 40s timers spawning hints)
- Validate guesses and track correct guesses
- Implement round termination conditions (all guessed or timer expired)

### Architecture

#### Drawing Storage
```elixir
# lib/flamingo/game/drawing.ex
defmodule Flamingo.Game.Drawing do
  defstruct [:events, :drawer_id]

  def add_event(drawing, event), do: %{drawing | events: [event | drawing.events]}
end
```

#### Guess Validation
```elixir
# lib/flamingo/game/guess_validator.ex
defmodule Flamingo.Game.GuessValidator do
  def check_guess(guess, correct_word) do
    String.downcase(guess) == String.downcase(correct_word)
  end

  def get_word_outline(word, hint_level \\ 0) do
    # Based on hint level, reveal letters
  end
end
```

#### RoundInProgress Handler
```elixir
# lib/flamingo/game/phases/round_in_progress.ex
defmodule Flamingo.Game.Phases.RoundInProgress do
  @behaviour Flamingo.Game.PhaseHandler

  def start_phase(gs) do
    # Schedule hint timers (29s and 39s)
    # Return game state with timers registered
    {:ok, gs}
  end

  def handle_message(gs, player_id, message) do
    case message do
      %{"type" => "drawEvent"} -> handle_draw(gs, player_id, message)
      %{"type" => "guess"} -> handle_guess(gs, player_id, message)
      %{"type" => "chat"} -> handle_chat(gs, player_id, message)
      %{"type" => "clearDrawing"} -> handle_clear(gs, player_id, message)
    end
  end

  def handle_timeout(gs, :hint_30) do
    # Reveal hint level 1
    # Broadcast to guessers
    {:ok, gs}
  end

  def handle_timeout(gs, :hint_40) do
    # Reveal hint level 2
    {:ok, gs}
  end

  def handle_timeout(gs, :round_timer) do
    # Round ended due to time
    # Transition to RoundScoreDisplay → PhaseChangeAck
    {:ok, updated_gs, :phase_change_ack}
  end

  defp handle_draw(gs, player_id, %{"payload" => payload}) do
    # Validate player is drawer
    # Store draw event
    # Broadcast to guessers
    {:ok, updated_gs}
  end

  defp handle_guess(gs, player_id, %{"payload" => %{"guess" => guess}}) do
    # Check if guess is correct
    if GuessValidator.check_guess(guess, gs.word) do
      # Mark player as correct
      # Check if all have guessed → end round
      # Broadcast wordReveal to guesser, playerCorrect to others
      # Check termination condition
      {:ok, updated_gs, next_phase}
    else
      # Treat as chat message (incorrect guess)
      {:ok, updated_gs}
    end
  end
end
```

### Deliverables
- [ ] Draw event storage and broadcasting
- [ ] Guess validation logic
- [ ] Hint system with proper timing (29s, 39s)
- [ ] Correct guess detection and broadcast
- [ ] Chat message handling (including incorrect guesses as chat)
- [ ] Round termination conditions (all guessed OR timer)
- [ ] Integration tests for draw, guess, and hint flow
- [ ] Manual test: Full round - drawer draws, guessers guess, hints appear at right times, round ends correctly

### Key Considerations
1. **Draw Events:** Store as-is, replay-able format for game end
2. **Hints:** Deterministic (FNV-32a seed or Elixir's hash)
3. **State Mutation:** Use `Map.update` and immutable patterns
4. **Broadcast Timing:** Non-blocking sends to room

---

## Phase 5: Scoring & Round Completion (RoundScoreDisplay + RoundFinished)

### Goals
- Implement scoring calculations
- Display scores to players
- Manage round progression (drawer rotation, round counter)
- Handle game completion (all rounds done)

### Architecture

#### Scoring Module
```elixir
# lib/flamingo/game/scoring.ex
defmodule Flamingo.Game.Scoring do
  def calculate_round_scores(game_state, correct_guesses_map) do
    # correct_guesses_map: %{player_id => time_guessed_seconds}
    # Return: %{player_id => points}
    # First guesser: 400 pts - penalty
    # Other guessers: 50-350 pts
    # Drawer: -100 to +350 based on guesser count
  end

  def apply_scores(game_state, round_scores) do
    # Update player.score += round_scores[player_id]
    game_state
  end
end
```

### Deliverables
- [ ] Scoring calculation (matching Go logic exactly)
- [ ] RoundScoreDisplay phase handler (5s display)
- [ ] RoundFinished phase handler (apply scores, update round counter)
- [ ] Drawing history storage per player
- [ ] Game completion detection (all rounds done)
- [ ] Transition to GameOver or next RoundSetup
- [ ] Integration tests for scoring
- [ ] Manual test: Complete a full game, verify scores, see game over screen

---

## Phase 6: Game Completion & Replay (GameOver)

### Goals
- Send final scores and drawing histories
- Enable frontend to replay all drawings
- Clean up game state

### Architecture

#### GameOver Handler
```elixir
# lib/flamingo/game/phases/game_over.ex
defmodule Flamingo.Game.Phases.GameOver do
  def start_phase(gs) do
    # Compile drawing histories from gs.player_drawing_histories
    # Broadcast gameFinished with final scores + histories
    # Transition room back to lobby (new game)
    {:ok, gs}
  end
end
```

### Deliverables
- [ ] GameOver phase handler
- [ ] Drawing history compilation
- [ ] Frontend-compatible replay format
- [ ] Room reset to new lobby (or terminate game, return to empty lobby)
- [ ] Integration test for full game flow
- [ ] Manual test: Full game start-to-finish, see drawing replay

---

## Phase 7: Error Handling & Resilience

### Goals
- Implement player disconnection handling
- Implement minimum player requirements
- Handle mid-game player drops gracefully
- Log errors appropriately

### Architecture

#### Player Disconnect Handler
```elixir
# In GameChannel.terminate/3
def terminate(_reason, socket) do
  room_pid = socket.assigns.room_pid
  player_id = socket.assigns.player_id
  Flamingo.Room.unregister_player(room_pid, player_id)
end
```

#### Game Resilience
```elixir
# In Game GenServer
# Handle min_players check before each phase
# If players drop below 2, transition to GameOver or Error phase
```

### Deliverables
- [ ] Graceful player disconnection in room
- [ ] Minimum player enforcement (abort game if < 2)
- [ ] Error phase handler (stub → full implementation)
- [ ] Logging for debugging
- [ ] Tests for disconnection scenarios

---

## Phase 8: Frontend Integration & Testing

### Goals
- Ensure existing SolidJS frontend works with new Elixir backend
- Test all game flows end-to-end
- Performance validation

### Verification Checklist
- [ ] Room creation returns correct JSON
- [ ] WebSocket upgrade succeeds
- [ ] All message types are correctly formatted
- [ ] Phase transitions happen at right times
- [ ] Scores are calculated correctly
- [ ] Drawing replay works

### Manual Testing
```bash
# Start Elixir server
mix phx.server

# Start frontend dev server (existing)
cd frontend && npm run dev

# Test in browser
# 1. Create room (POST /create-room)
# 2. Join via WebSocket
# 3. Start game
# 4. Play full round
# 5. Verify scores and drawing replay
```

---

## Phase 9: Optimization & Production Readiness

### Goals
- Performance profiling
- Elixir-specific optimizations (if needed)
- Clustering support (optional, beyond scope)
- Error logging and monitoring

### Deliverables
- [ ] Benchmarks for game loop
- [ ] Supervisor restart strategies
- [ ] Graceful shutdown handling
- [ ] Load testing (multiple concurrent games)

---

## Parallel Work: Keep Go Backend Running

### Strategy
During the migration, **maintain the Go backend** for fallback. Configuration options:
- Environment variable to select which backend to use
- Load balancer to route to either backend
- Feature flags for gradual rollout

### Recommendation
1. Run **Elixir backend alongside Go** during Phase 1-3
2. When Elixir passes Phase 4 (full game loop), switch main traffic
3. Keep Go as failover for stability-critical deployments
4. Eventually deprecate Go backend once Elixir is battle-tested

---

## Testing Strategy Overview

### Unit Tests
- Scoring calculations
- Word selection and hints
- Guess validation
- Message parsing

### Integration Tests
- Room creation and cleanup
- Player join/leave flow
- Full game phases
- Phase transitions

### Manual/E2E Tests
- Connect multiple clients
- Play full game
- Verify WebSocket message flow
- Check drawing replay accuracy

### Load Testing
- Multiple concurrent games
- Rapid player joins/leaves
- Message throughput

---

## Technical Decisions & Rationale

### Why OTP GenServer for Rooms & Games?
- **Concurrency:** Goroutines ↔ Elixir processes (lightweight, millions possible)
- **State Management:** GenServer ↔ Go channels + Mutex (safer, fewer race conditions)
- **Fault Tolerance:** Supervisor trees automatically restart crashed processes
- **Message Passing:** Natural fit for turn-based game communication

### Why Phoenix.Channel for WebSocket?
- **First-class support:** Built-in WebSocket, presence, broadcasting
- **Compatible:** JSON protocol matches existing frontend exactly
- **Scalable:** Channel behavior supports features like presence tracking
- **Tested:** Used in production by many Elixir apps

### Why Keep JSON Protocol?
- **Zero frontend changes:** Existing SolidJS client works as-is
- **Gradual migration:** No need to rewrite frontend yet
- **Validation:** JSON schema can be enforced in tests

### Why Incremental Phase-by-Phase Migration?
- **Testability:** Each phase can be manually tested in isolation
- **Confidence:** Reduces risk of large monolithic rewrites
- **Rollback:** Can revert to Go at any phase if issues arise
- **Learning:** Team learns Elixir patterns as they build

---

## Timeline Estimate

| Phase | Complexity | Estimated Time |
|-------|-----------|-----------------|
| 0: Foundation | Low | 2-3 days |
| 1: Room & Lobby | Low-Medium | 3-4 days |
| 2: Phase Management | Medium | 4-5 days |
| 3: Round Setup | Low-Medium | 2-3 days |
| 4: Round In Progress | High | 5-7 days |
| 5: Scoring | Medium | 2-3 days |
| 6: Game Over & Replay | Low | 2 days |
| 7: Error & Resilience | Medium | 2-3 days |
| 8: Integration & Testing | Medium | 3-4 days |
| 9: Optimization | Low-Medium | 2-3 days |

**Total Estimate:** 6-8 weeks for full production-ready migration

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|-----------|
| Elixir team skill gap | Medium | High | Pair programming, code reviews, documentation |
| Performance regression | Low | Medium | Benchmarking phase 4, load testing phase 8 |
| Frontend incompatibility | Low | High | Early integration testing (phase 8) |
| Data loss (in-memory) | N/A | N/A | Define persistence requirements early |
| WebSocket edge cases | Medium | Low | Extensive manual testing, chaos testing |

---

## Success Criteria

### Phase 1 Complete ✅
- [ ] Multiple clients can join a room via WebSocket
- [ ] Player list updates for all clients
- [ ] Host can start game

### Phase 4 Complete ✅
- [ ] Full game round executes (setup → drawing → scoring)
- [ ] Drawing events are captured and displayed in real-time
- [ ] Guesses are validated and marked correct/incorrect

### Phase 6 Complete ✅
- [ ] Game finishes with correct scores
- [ ] Drawing replay works in frontend
- [ ] Clean room state for new game

### Phase 9 Complete ✅
- [ ] Elixir backend passes all load tests (>100 concurrent games)
- [ ] Latency is comparable to or better than Go
- [ ] No data loss or corruption under load

---

## Next Steps

1. **Kick off Phase 0:** Set up Phoenix project, WebSocket endpoint, basic tests
2. **Review & Approve:** Confirm architecture decisions with team
3. **Assign Ownership:** Designate phase leads for parallelization
4. **Begin Phase 1:** Start with room management, iterate weekly
5. **Continuous Integration:** Ensure tests pass after each phase
6. **Document:** Keep docs in sync as architecture evolves

