## Problem Statement

Players currently reach a Game finished screen that shows final Scores, but the Drawings created during the Game disappear from the experience. This makes the end of a Game feel abrupt: players can see who won, but they cannot revisit the moments that made the Game fun.

The final results also need to represent the whole Game, not just the Players still present in the Room. A Player who leaves before the Game ends should remain part of that Game's final results, and any Drawings they created should remain available in the showcase.

## Solution

Add a final Game Drawing showcase to the Game finished screen.

The final screen keeps the final Score table on the left and shows the selected Player's Drawings on the right. The winning Player is selected by default. Each Score row is selectable; selecting another Player changes only the Drawing showcase, not the final Score ranking. The selected row has a clear visual selection state and a small replay control near the Score.

The showcase shows all Drawings created by the selected Player during the current Game, in chronological order with the first Drawing at the top. Each Drawing tile displays its Round number and Word. The selected Player's Drawings replay automatically when the final screen opens and whenever a different Player is selected. All Drawings for the selected Player replay at the same time, one stored drawing event every roughly 25 milliseconds, and remain visible after their replay completes. Empty Drawings render immediately.

Drawings are current-Game history only. They survive for the finished Game while the Room is still showing that Game's final results, but they are not long-term gallery artifacts and should not be kept for later Games in the same Room.

## User Stories

1. As a Player, I want to see Drawings at the end of a Game, so that the final screen celebrates more than just Scores.
2. As a Player, I want final Scores to remain visible on the left side of the Game finished screen, so that I can still understand the Game outcome immediately.
3. As a Player, I want the winning Player selected by default, so that the final screen starts with the Game winner's Drawings.
4. As a Player, I want Score rows to be selectable, so that I can choose whose Drawings I am viewing without a separate selector.
5. As a Player, I want the selected Score row to look selected, so that I know whose Drawings are currently shown.
6. As a Player, I want the final Score ranking to stay fixed when I select another Player, so that browsing Drawings does not change the Game result order.
7. As a Player, I want a replay control on the selected Score row, so that I can watch that Player's Drawings animate again.
8. As a Player, I want selecting a different Player to stop the current replay and start the newly selected Player's replay, so that the screen responds directly to my selection.
9. As a Player, I want all of the selected Player's Drawings to start replaying at the same time, so that switching Players feels immediate.
10. As a Player, I want each Drawing replay to render one stored event at a steady cadence, so that simple Drawings appear quickly and complex Drawings take naturally longer.
11. As a Player, I want a starting replay cadence of about 25 milliseconds per event, so that the animation feels quick enough to review.
12. As a Player, I want Drawings to remain visible after their replay completes, so that the showcase settles into a stable gallery.
13. As a Player, I want empty Drawings to render immediately, so that a blank Drawing does not look like a broken animation.
14. As a Player, I want each Drawing to show its Word, so that I can understand what the Drawer was trying to illustrate.
15. As a Player, I want each Drawing to show its Round number, so that I can place it in the Game timeline.
16. As a Player, I want Drawings ordered chronologically, so that the selected Player's Game history reads naturally from top to bottom.
17. As a Player, I want the selected Player context to identify the Drawer, so that each Drawing tile does not repeat the same Player name.
18. As a Player, I want every completed Turn to produce a Drawing, even if the canvas is blank, so that the Game history is complete.
19. As a Player, I want a partial Drawing to be preserved if a Turn is interrupted, so that the showcase reflects what happened in the Game.
20. As a Player, I want a Drawer disconnect to preserve the partial Drawing but award no Score for that Turn, so that the final results are fair.
21. As a Player, I want a Game that ends early to still show the Game finished screen, so that Drawings and final Scores collected so far are not lost.
22. As a Player, I want an early Game finish during active drawing to preserve the partial Drawing and award no Score for that interrupted Turn, so that the final results are consistent.
23. As a Player, I do not want an interrupted Word choice to create a Drawing, so that only Turns with a chosen Word and drawing interval appear in the showcase.
24. As a Player, I want Words to be public on the final screen, so that every Drawing label is understandable after the Game finishes.
25. As a Player who joined late and never drew, I want to remain in the final Score table, so that my Game participation is still represented.
26. As a Player viewing someone with no Drawings, I want a clear empty state, so that I know there are no Drawings for that Player this Game.
27. As a Player who left before the Game ended, I want my Score and Drawings to remain in final results, so that leaving does not erase my Game history.
28. As a Player still present in the Room, I want absent Players skipped for future Drawer selection, so that the Game does not wait on someone who is not there.
29. As a reconnecting Player, I want the Game finished screen to select the winning Player by default and replay their Drawings once, so that rejoining behaves like arriving at final results normally.
30. As a viewer, I want my selected Player to be local to my browser, so that another Player browsing Drawings does not change my final screen.
31. As a Host, I do not need a Play again path as part of this feature, so that the work stays focused on final results.
32. As a developer, I want Drawings stored as replayable drawing events, so that the final screen can animate them without adding image storage.
33. As a developer, I want replay to use the stored event array exactly as captured, so that clear events replay if present and undo history does not require a new action model.
34. As a developer, I want server-rendered tests to assert Drawing metadata and final Score behavior, so that tests do not depend on animation frame timing.
35. As a developer, I want the drawing replay logic isolated behind a small client-side interface, so that final result rendering and canvas animation can evolve separately.

## Implementation Decisions

- Build only in the Elixir LiveView implementation.
- Treat Drawing as a Game-scoped domain concept. A Drawing belongs to one Turn, one Game, and one Drawer.
- Store Drawings as replayable drawing event arrays, not rendered image snapshots.
- A Drawing history item should include enough stable Game history to render final results: Drawer, Word, Round number, Turn order, and drawing events.
- Introduce a deep, testable Drawing history abstraction that records completed and interrupted Drawings behind a small interface. This keeps GameServer from accumulating ad hoc history manipulation.
- Update the Game server state to keep current-Game participants separately from currently active Players, so departed Players can remain in final results while absent Players are skipped for future Drawer selection.
- Update Turn completion so normal timeouts, all-guessed Turns, and interrupted Turns record a Drawing.
- Drawer disconnect during active drawing ends the Turn immediately, records the partial Drawing, and awards no Score for that Turn.
- Drawer disconnect during Word choice does not create a Drawing.
- If active Players fall below the Game mode's Minimum player count after a Game has started, the Game finishes early and shows final results instead of returning directly to the Lobby.
- If an early Game finish happens during active drawing, record the partial Drawing and award no Score for the interrupted Turn.
- Keep final results scoped to the current Game. Do not persist Drawings across later Games in the same Room.
- Extend the public game facade only as needed to expose final Drawing history through existing state retrieval and PubSub messages.
- Update the Game finished LiveView state to include final Drawing history and local selected Player state.
- Select the winning Player by default using the same ordering as the final Score table, with existing player order as the tie-breaker.
- Keep Player selection local to each LiveView process. Do not broadcast selected Player changes.
- Use selectable Score rows as the Player selector. The selected row should have a clear visual selected state and a replay control near the Score.
- Keep the final Score table order fixed while changing only the selected Player's Drawing showcase.
- Render the right-side showcase as a list or tiled layout depending on available screen space. Phone optimization is out of scope.
- Show Round number and Word on each Drawing tile. Do not repeat the selected Player name on every tile.
- Show an empty state when the selected Player has no Drawings in the Game.
- Add a read-only drawing replay hook for final result tiles. It should reset each selected Player's canvases to blank, replay all selected Drawings simultaneously, and leave each canvas in its final state.
- Use a starting replay cadence of about 25 milliseconds per stored drawing event.
- Empty Drawings render immediately.
- Replay should faithfully apply the stored events. If a clear event exists in the stored event array, replay it. Do not add a separate raw action history to represent undone strokes.
- Server-rendered HTML should contain the Drawing metadata and event payload needed by the hook, while animation remains a client-side behavior.

## Testing Decisions

- Good tests should verify external behavior: final Game state, final Score visibility, Drawing history contents, Player selection rendering, and PubSub/LiveView outcomes. They should not assert private helper functions or animation frame-by-frame behavior.
- Test the Drawing history abstraction directly because it should be a deep module with a small interface and meaningful internal rules.
- Test the Game server behavior for normal Turn completion, blank Drawing recording, partial Drawing recording, Drawer disconnect with no Score, interrupted Word choice without Drawing, early Game finish, departed Player final results, and absent Player Drawer skipping.
- Test final result ordering and winning Player default selection through LiveView behavior.
- Test that final Score rows remain sorted by rank when another Player is selected.
- Test that departed Players remain visible in final results and can have Drawings shown.
- Test that a Player with no Drawings gets a clear empty state.
- Test reconnect or late arrival to `game_ended` state so the final screen receives final Scores and Drawing history.
- Treat canvas replay animation as a browser hook concern. Unit-level testing can cover event scheduling logic if extracted, but LiveView tests should only assert that the hook has the expected event payload and replay trigger.
- Prior art exists in the current Game server tests for phase transitions, scoring, Player leave behavior, and final Game end broadcasts.
- Prior art exists in the current LiveView tests for keeping final Scores visible after a Player leaves.

## Out of Scope

- Long-term Drawing galleries outside the current Game.
- Persisting Drawings across server restarts.
- Keeping Drawing history after the Room moves on to a later Game.
- A Play again or Back to lobby flow.
- Full phone-screen optimization.
- Rendered image snapshot storage or export.
- Replaying discarded undo history that is not present in the stored event array.
- Changing the core drawing tools beyond what is necessary to replay stored Drawing events.
- Adding new Game modes.
- Work on the retired Go/SolidJS implementation.

## Further Notes

- The domain glossary now uses **Drawing** as the canonical term. Avoid "picture" and "sketch" in product and implementation naming unless quoting user-facing copy that already exists.
- This feature exposes existing implementation gaps: current Players and final Game participants are conflated, and Drawer disconnect behavior currently does not match the resolved domain language.
- The feature should maintain the current ephemeral Room model while preparing the code for a future where a Room can host multiple Games over time.
