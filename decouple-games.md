# Decoupling Rooms and Game Modes

## Goal

Refactor Flamingo so rooms, connected members, and game-mode state have clear ownership while preserving the current Scribble game and leaving room for additional modes.

The migration should remain deployable at every stage. After each vertical slice, exercise the application in real browsers in the orb and play a complete game. Do not add Playwright or another browser-test framework; focused ExUnit and LiveView tests remain the automated suite.

## Agreed architecture

Keep one authoritative `RoomServer` process per room. It serialises joins, connection changes, game commands, and timeouts, but delegates in-process decisions to pure modules.

```text
Web adapters
    |
    v
Flamingo.Rooms
    |
    v
Flamingo.RoomServer
    |-- process monitors
    |-- timer runtime and stale-timer protection
    |-- registered connection delivery
    |-- recipient-safe ordered snapshots and drawing deltas
    |-- atomic coordination of room and mode transitions
    |
    |-- Room.Members
    |     |-- seats and resume credentials
    |     |-- names and room order
    |     |-- host succession
    |     `-- semantic connection state
    |
    `-- GameModes.Scribble
          |-- participation and spectator state
          |-- phases, rounds, and drawer rotation
          |-- words, guesses, drawings, and hints
          |-- scoring and final results
          `-- viewer-specific projections
```

Do not create separate lobby, connection, and game GenServers. A room is the natural serialisation unit; separate processes would turn joins, disconnects, and game transitions into cross-process coordination problems.

### Room lifecycle versus mode phase

The room exists before, during, and after a match:

```text
:lobby -> {:playing, mode_instance_id} -> {:finished, result}
```

Scribble independently owns its phases:

```text
:word_choice -> :playing -> :turn_reveal -> ...
```

A standalone `Room.Lobby` module is not currently justified. `RoomServer` owns the small generic lifecycle, `Room.Members` owns the host and seats, and the mode owns settings, readiness, and active-game admission policy. Extract a lobby module only if meaningful shared lobby behaviour emerges later.

## Ownership rules

- A **room member** is a durable seat with a public seat ID and private resume credential.
- A **connection** is an ephemeral LiveView process attached to a member. One member may have multiple connections because of duplicated tabs, multiple devices, or reconnect overlap.
- A **mode participant** is the mode-specific interpretation of a room member. They may be active, spectating, on a team, or otherwise classified by the mode.
- Host is a room-member role. Drawer is a Scribble role.
- Scores belong entirely to the game mode. `RoomServer` and `Room.Members` do not know their representation or scale.
- `RoomServer` owns real PIDs, monitor references, timer references, and notification delivery.
- `Room.Members` owns pure member and connection-count semantics.
- `ScribbleLive` renders Scribble settings, participation, scores, controls, and results. Future modes receive their own mode-specific LiveViews.

## Game-mode interface

Commands, admission, connection changes, permanent removal, and timeouts have different invariants and should not be placed into one unstructured transition function.

The concrete Scribble implementation should establish this expected shape:

```elixir
Scribble.start(members, settings, context)
Scribble.admit_member(state, candidate, context)
Scribble.connection_changed(state, seat_id, status, context)
Scribble.remove_member(state, seat_id, reason, context)
Scribble.command(state, actor_id, command, context)
Scribble.timeout(state, timer_key, context)
Scribble.view(state, viewer_id)
```

Expected distinctions:

- `admit_member` may accept or reject a proposed room join. `RoomServer` commits the room member and mode transition together or commits neither.
- `connection_changed` receives only semantic `:online` and `:offline` transitions. It cannot reject an authoritative connection fact.
- `remove_member` receives a permanent removal and its reason, such as `:left` or `:expired`.
- `command` handles mode-specific, authenticated player intent.
- `timeout` receives only semantic timer keys after `RoomServer` has rejected stale runtime messages.
- `view` returns a viewer-specific projection and must not leak hidden state.

State-changing functions return a narrow transition result containing the next state, optional command reply, logical timer intents, and whether the mode continues or finishes. The mode does not call `Process.send_after`, PubSub, or the wall clock directly.

Do not introduce a formal `GameMode` behaviour until a second mode exists and proves which parts of this concrete interface are genuinely common.

## Connection semantics

`Rooms.connect/2` registers and monitors the calling LiveView process. The mode does not see individual tabs, PIDs, or monitor references.

```text
0 -> 1 connections: member became online; notify the mode
1 -> 2 connections: no mode event
2 -> 1 connections: no mode event
1 -> 0 connections: member became offline; notify the mode and start grace
grace expires:       permanently remove the member and notify the mode
```

An explicit leave is different from a connection ending: it permanently removes the seat. `ScribbleLive.terminate/2` must not call leave.

## Safe ordered views

The current snapshot-then-subscribe flow can miss a mutation between reading state and subscribing. PubSub has no replay, and `ScribbleLive` currently reconstructs a second state machine from deltas. Raw state and shared events can also expose secret words and choices.

The improved flow is:

1. `Rooms.connect/2` authenticates the credential.
2. `RoomServer` registers and monitors the caller in the same serialised call.
3. It applies any online transition.
4. It returns a complete safe viewer-specific snapshot.
5. Later room mutations direct-send complete recipient-safe snapshots.
6. Drawing operations direct-send low-latency deltas to every connection except the exact originating PID.

Snapshots and drawing deltas are sent from the same `RoomServer` process, so Erlang preserves their order for each registered LiveView. A duplicated tab for the drawer receives deltas originating from the other tab, while the exact origin renders locally without receiving an echo.

Use full projected views for connection, phase changes, membership changes, and other ordinary room mutations. Keep drawing operations as safe low-latency deltas. The complete authoritative drawing remains in connection snapshots so late joins and reconnects begin with the correct baseline before receiving subsequent deltas.

## Scribble late joining

Scribble allows room members to join while a game is active. A member joining after the current round has begun spectates until the next round.

During the current round, the late member:

- can see the room, drawing, and public game state;
- cannot guess or draw;
- does not count toward turn completion;
- is not in current-round drawer selection;
- has a Scribble score of zero.

At the next round transition, Scribble promotes eligible spectators before selecting the first drawer. They can then guess and enter drawer rotation. A member joining during the final round remains a spectator through game end and becomes a normal participant in a rematch.

## Vertical migration slices

### Baseline: play the current game

Before changing code, run the app in the orb and play a complete two-player game:

1. Alice creates a room.
2. Bob joins.
3. Alice configures one-round Scribble with deterministic custom words.
4. Each drawer selects a word and draws.
5. Each guesser sees the drawing and guesses correctly.
6. Both players reach the result screen with scores and final drawings.

This is the browser behaviour to preserve after every slice.

### Slice 1: establish room vocabulary and safe views

#### Change

- Rename `Games` to `Rooms`.
- Rename `GameSupervisor` to `RoomSupervisor`.
- Rename `GameServer` to `RoomServer`.
- Rename `GameLive` to `ScribbleLive`.
- Record the room mode as `:scribble`.
- Introduce viewer-safe room snapshots.
- Stop returning raw `RoomServer` state to the web layer.
- Remove secret words, word choices, and credentials from unauthorised views and shared messages.

Keep the game implementation inside `RoomServer` temporarily. Do not combine this slice with game-state extraction.

#### Automated verification

- Update existing tests to the new names.
- Verify drawer and guesser projections expose only authorised state.
- Verify credentials never appear in public member data.
- Run `mix precommit`.

#### Browser acceptance

Play the complete two-player game. During play, verify the drawer sees the chosen word while the guesser sees only its masked projection.

### Slice 2: fix connections and add safe direct notifications

#### Change

- Add `Rooms.connect/2`, `Rooms.snapshot/1`, and explicit `Rooms.leave/1` semantics.
- Register and monitor the calling LiveView process.
- Track multiple connections per member.
- Remove `ScribbleLive.terminate/2` calling leave.
- Make connect-and-snapshot one serialised operation.
- Add recipient-safe direct snapshot notifications from the authoritative room process.
- Keep drawing operations as ordered low-latency deltas that exclude only the exact origin.
- Include the complete current drawing in connection snapshots for late joins and reconnects.

#### Automated verification

- Two connections attached to one seat.
- Closing one connection leaves the member online.
- Closing the final connection marks the member offline.
- Reconnect before grace expiry.
- Stale `:DOWN` and stale disconnect timers.
- Exact-origin drawing delivery and duplicate-tab synchronization.
- Complete drawing baselines on late join and reconnect.
- Run `mix precommit`.

#### Browser acceptance

1. Play the complete two-player game.
2. Duplicate Alice's game tab, close one tab, and verify Alice remains online and can continue from the other.
3. Close Alice's final tab and verify Bob sees her disconnect.
4. During another game, draw several strokes, reload Bob, and verify he reconnects into the correct phase with the complete drawing and can finish the game.

### Slice 3: separate room members from Scribble state

#### Change

Introduce `Room.Members` and move complete ownership of these concepts into it:

- seat IDs and resume credentials;
- display names and room order;
- host assignment and succession;
- semantic online/offline state.

Remove score from room member records and move it into explicitly Scribble-owned state. The rest of the Scribble implementation may still be inside `RoomServer` during this slice.

#### Automated verification

- Host assignment and succession.
- Connection status transitions.
- Score unaffected by room-role changes.
- Disconnect preserving Scribble score.
- Finished results surviving later member removal.
- Prefer snapshot assertions over raw server-state assertions.
- Run `mix precommit`.

#### Browser acceptance

Play the complete game and verify host controls, online state, scoring, final standings, and that results remain visible if a member leaves afterward.

### Slice 4: extract the pure Scribble engine

#### Change

Create `GameModes.Scribble` and move into it:

- settings and participants;
- participation and spectator status;
- scores;
- phases and drawer rotation;
- words and word choices;
- drawings and undo;
- guesses and hints;
- turn and round progression;
- final results;
- viewer-specific projections.

`Scribble` returns pure transitions and logical timer intents. `RoomServer` remains responsible for process monitors, runtime timer references, stale-message protection, committing state, and notification delivery.

Move one coherent transition family at a time without dual-writing old and new mode state:

1. Start and word choice.
2. Select word and enter playing.
3. Drawing operations.
4. Guessing and scoring.
5. Turn reveal.
6. Drawer and round progression.
7. Hints.
8. Game finish.

#### Automated verification

Replace appropriate process-heavy tests with direct Scribble transition tests covering complete games, guesses, hints, scoring, disconnect consequences, final drawings, and safe projections. Keep focused `RoomServer` tests for timer and process semantics. Run `mix precommit`.

#### Browser acceptance

Play the complete two-player game and check settings, word visibility, canvas delivery, drawing, guesses, scores, drawer rotation, final drawings, and standings.

### Slice 5: implement late joining as Scribble spectating

#### Change

Implement `Scribble.admit_member/3` so a member joining after the round begins is recorded as spectating until the next round. Promote eligible spectators at the next round transition before selecting the first drawer.

#### Automated verification

- Joining during play creates a spectator.
- Spectators cannot guess or draw.
- Spectators do not block turn completion.
- Spectators are not selected as current-round drawers.
- The next round promotes eligible spectators.
- Promoted players can guess and enter drawer rotation with score zero.
- Final-round joiners remain spectators through game end.
- Reconnect does not change eligibility.
- Run `mix precommit`.

#### Browser acceptance

1. Alice creates a two-round game and Bob joins.
2. Start Scribble and begin drawing in the first round.
3. Charlie joins during `:playing`.
4. Verify Charlie sees the game and a spectator state but has no guess or drawing controls.
5. Verify Charlie does not prevent the current turn from finishing.
6. Complete the remaining first-round turns.
7. Verify Charlie is promoted when the next round starts.
8. Verify Charlie can guess and later enters drawer rotation.
9. Complete the game and verify all three players' results.

### Slice 6: remove migration scaffolding

#### Change

Remove:

- raw room/game state access from callers;
- old module aliases and compatibility functions;
- obsolete PubSub gameplay tuples;
- duplicated member or score fields;
- old phase reconstruction in `ScribbleLive`;
- tests that bypass the new interfaces without a process-level reason.

Keep `Rooms` interface tests, pure `Room.Members` and `Scribble` tests, focused `RoomServer` runtime tests, and `ScribbleLive` integration tests.

#### Verification

- Run `mix precommit`.
- Play a complete two-player game.
- Reload a guesser during drawing and finish the game.
- Exercise duplicate-tab connection handling.
- Play the three-player late-join game.

## Stage gate for every slice

```text
1. Add or update focused tests for the changed ownership.
2. Run mix precommit.
3. Start or update the app's supervised orb service.
4. Play one complete Scribble game in real browsers.
5. Exercise the slice-specific browser scenario.
6. Move to the next slice only after both automated and browser checks pass.
```

The browser checks are driven directly in the orb; no browser-test framework or committed automation harness is part of this plan.
