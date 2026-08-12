---
name: verifying-gameplay-end-to-end
description: "Verifies substantial Flamingo gameplay features end to end with synchronized browser players and a reviewable video artifact. Use for large gameplay features, multiplayer or game-flow changes, end-to-end visual verification, and requests for gameplay video evidence."
---

# Verifying Flamingo Gameplay End to End

Exercise the real Phoenix LiveView game with multiple browser sessions, prove important synchronized states, and leave a concise `.webm` artifact reviewers can watch.

## Before the browser

1. Read the changed game mode, its LiveView/components, `Flamingo.RoomServer`, and nearby LiveView/server tests. Define the scenario, players, transitions, and assertions before interacting.
2. Run the focused tests first. Use the existing tests and their selectors as the behavioral map; use `mix test <test-file>` for targeted checks and `mix precommit` when the feature work is complete.
3. Load the installed browser CLI instructions instead of guessing its API:

   ```bash
   agent-browser skills get core --full
   ```

4. Check `amp orb service list`. Reuse a healthy Flamingo/Phoenix service if one already owns the intended port. Otherwise start it as a supervised orb service so it survives pauses and CLI updates:

   ```bash
   amp orb service start flamingo-e2e --command 'mix phx.server' --portal
   ```

   Use the loopback URL printed by the service tooling only inside browser automation. Share only the returned Amp portal URL with people. Inspect startup/runtime output with `amp orb service status flamingo-e2e` and `amp orb service logs flamingo-e2e`.

## Deterministic multiplayer setup

- Use one isolated `agent-browser` session per player, with stable descriptive names such as `flamingo-host` and `flamingo-guest`. Keep the host and guest commands explicit; never reuse one session for two players.
- Use short, non-sensitive names such as Alice and Bob. Create the room through `/` as Alice with `#name-input` and `#create-room-button`. Read the room code from the resulting `/game/:room_id` URL or lobby, then join through `/` as Bob with `#name-input`, `#room-code-input`, and `#join-button`.
- Wait for both `#lobby-player-row-*` entries in both sessions before starting. Alice is host because the first member owns the new room. Verify only Alice sees `#settings-form` and `#start-game-button`.
- Prefer two players unless the behavior specifically depends on more. Use one round, the minimum supported 15-second turn, and unique custom words with **Include standard words** off when word identity matters. Record the exact settings and player roles in the report.
- Use selector/state waits, not blind sleeps: wait for the next phase selector, for a prior selector to disappear, or poll a DOM condition with `eval`. After every player action, confirm the expected phase in **both** sessions before continuing. Retry an interaction only after inspecting the DOM, page errors, console, and server logs; never blindly repeat a non-idempotent submit.

Example session shape (adapt the internal URL/port to the running service):

```bash
HOST=flamingo-host
GUEST=flamingo-guest
agent-browser --session "$HOST" open http://127.0.0.1:4000/
agent-browser --session "$GUEST" open http://127.0.0.1:4000/
agent-browser --session "$HOST" snapshot -i
```

Use `snapshot -i` again after each transition because element refs are not stable across LiveView patches. Prefer durable repository IDs over text or generated refs for assertions and actions.

## Exercise the complete public flow

Use the feature's real public controls. Do not call `Rooms`, send server messages, mutate LiveView state from JavaScript, or skip transitions merely to make the recording short.

### Scribble / Constraint Roulette

1. Host configures `#settings-form` and starts with `#start-game-button`.
2. Identify the drawer from the synchronized UI. In that player's session, choose one of the rendered `select_word` buttons. Verify the drawer sees the word and drawing controls while the guesser sees blanks/hints and `#guess-form`.
3. Draw through the actual `#drawing-canvas canvas` with `agent-browser mouse` operations. Assert the remote player receives the visible stroke; for constraints, assert the rule is shown and actually affects the interaction under test.
4. Submit at least one incorrect guess and verify it appears appropriately in `#game-feed`, then submit the exact selected custom word. Verify score/correct-guess state in both sessions and `#turn-reveal-score-gains` during reveal.
5. Complete every configured turn. For one round with two players, each player must draw once. Verify `#final-score-rows`, winner/order, expected scores or relative score changes, and any final drawing showcase affected by the feature.

### Telephone

1. Host chooses Telephone in `#settings-form`, sets deterministic custom prompts, starts, and confirms both players redirect to `/game/:room_id/telephone` at `#telephone-prompt-phase`.
2. Each player selects a private choice under `#telephone-prompt-choices`. Verify one player's choice is not exposed to the other before reveal.
3. In each `#telephone-draw-phase`, draw through `#telephone-drawing-canvas canvas`, submit with `#submit-telephone-drawing`, and verify the waiting state plus synchronization to the next phase only after all online players submit.
4. In each `#telephone-guess-phase`, inspect the received drawing, submit a unique guess through `#telephone-guess-form`, and verify both players reach `#telephone-reveal-phase`.
5. On reveal, verify guests see `#waiting-for-reveal-host`, only the host sees `#advance-telephone-reveal`, entries accumulate under `#revealed-entries`, and votes update on both clients. Advance every chain/link to `#telephone-awards`; verify awards and host/non-host controls.

For disconnect, reconnect, timeout, host-transfer, late-join, or spectator work, add only the relevant disruption to the normal flow. Prove both the disrupted client and an unaffected client converge on the same server-owned phase. Preserve the resume URL inside the browser session; do not expose its `resume_token` in reports or recordings.

## Evidence and recording

Gather evidence while exploring, then record a clean, deliberate pass rather than a debugging session.

1. Before recording, set a viewport that keeps the important controls visible, clear stale console/error output, and rehearse the actions. Start the recording only after room/player setup unless setup itself is under test.
2. Record the primary player's session to:

   ```bash
   mkdir -p .amp/in/artifacts
   agent-browser --session "$HOST" record start .amp/in/artifacts/<feature>-gameplay.webm
   # Perform the concise important flow while driving other player sessions as needed.
   agent-browser --session "$HOST" record stop
   ```

3. Make the video self-explanatory: visibly show the configured lobby or starting state, each important intermediate phase, multiplayer-dependent updates, and the final result. Keep waits long enough to read but remove dead time. A focused feature video is preferable to a long exhaustive recording.
4. At each assertion point, capture machine-checkable evidence with `get`, `is`, `snapshot`, or `eval`; do not treat the video alone as proof. At the end inspect, for **every player session**:

   ```bash
   agent-browser --session "$HOST" errors
   agent-browser --session "$HOST" console
   agent-browser --session "$GUEST" errors
   agent-browser --session "$GUEST" console
   amp orb service logs flamingo-e2e
   ```

   Explain relevant warnings; do not hide failures by clearing them after the run. Confirm the WebM exists, is non-empty, and opens with `ffprobe` or `view_media`. Watch the final artifact yourself.
5. Never record real credentials, tokens, private rooms, personal data, environment values, or unrelated tabs. Keep browser chrome/address bars out of frame where possible. Do not paste resume-token URLs into logs or the report. Delete failed takes and any screenshots/traces that are not useful review artifacts.

## Temporary state-reaching patches

A small temporary patch to a LiveView is permitted only when a difficult state cannot practically be reached through the public UI (for example, shortening a long display-only wait during repeated verification).

- Prefer the real public path and server-owned transitions first.
- Keep the patch minimal, local, clearly marked `TEMP E2E`, and uncommitted. Document its file, exact effect, and why it was necessary.
- Never use it to bypass, force success in, or replace the behavior being tested. Do not fake multiplayer messages, scores, permissions, submissions, synchronization, or final results.
- Save the pre-patch diff, remove the patch before the final pass, and rerun the affected assertion against production code whenever practical.
- Before completion, inspect `git diff` and `git status --short`. Compare against the known pre-existing worktree state and verify no `TEMP E2E` marker or other test-only production change remains. Never revert unrelated user/agent changes.

## Completion report

Report:

- a clickable link to `.amp/in/artifacts/<feature>-gameplay.webm`;
- the scenario and settings exercised;
- every player name and role/session;
- the important intermediate and final assertions, including multiplayer synchronization and browser/console/server evidence;
- focused tests and final checks run;
- any temporary patch used and confirmation it was removed;
- limitations, untested branches, warnings, or recording omissions.

Do not claim end-to-end verification if the flow did not reach its real final state, either player had unexplained page/console/server errors, the final code still contains a test-only patch, or the video was not inspected.
