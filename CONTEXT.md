# Flamingo

Flamingo is a real-time social drawing game where players gather in a shared room and play game sessions together.

## Language

**Room**:
A temporary group of players gathered under a shared room code.
_Avoid_: Match, server

**Game**:
A playable session that starts inside a room and runs according to one game mode.
_Avoid_: Room, lobby

**Game mode**:
The ruleset that defines how a game in a room is played.
_Avoid_: Variant, template

**Minimum player count**:
The smallest number of active players required for a game mode to remain valid.
_Avoid_: Quorum

**Game settings**:
The configuration values chosen for a specific game when it starts.
_Avoid_: Room settings, lobby settings

**Lobby**:
The room state where players gather and prepare before a game starts.
_Avoid_: Room, game

**Score**:
A player's points within a single game.
_Avoid_: Rank, lifetime points

**Word**:
The hidden prompt the drawer is trying to illustrate during a single turn.
_Avoid_: Phrase, answer

**Word choices**:
The set of candidate words offered to the drawer for a turn.
_Avoid_: Custom prompt, free text

**Word choice**:
The step in a turn where the drawer selects one word from the offered choices.
_Avoid_: Setup detail, hidden implementation step

**Drawing**:
The visual image a drawer creates during a turn.
_Avoid_: Picture, sketch

**Room code**:
The shareable identifier players enter to join a room.
_Avoid_: Room name, invite code

**Player**:
A person participating in a room.
_Avoid_: User, client, connection

**Host**:
The player who controls a room and can start games in it.
_Avoid_: Owner, admin, moderator

**Drawer**:
The player whose current turn is to illustrate the hidden word.
_Avoid_: Artist, presenter

**Guesser**:
A player who is not currently drawing and is trying to identify the hidden word.
_Avoid_: Viewer, audience

**Turn**:
One drawing-and-guessing interval led by a single drawer.
_Avoid_: Phase, tick

**Round**:
A cycle of turns intended to give each player a chance to draw once.
_Avoid_: Match, game

## Relationships

- A **Room** contains multiple **Players**
- A **Room** has exactly one **Room code**
- A **Room** has exactly one **Host** at a time
- A **Room** may be in the **Lobby** when no **Game** is active
- A **Room** can host multiple **Games** over time
- A **Player** in a **Room** participates in the active **Game** in that room
- A **Player** may participate in multiple **Games** within the same **Room**
- A **Player** who joins a **Room** during an active **Game** participates in that **Game** immediately
- A **Player** who joins during a **Round** may become the **Drawer** later in that same **Round**
- A **Player** who joins during an active **Turn** becomes a **Guesser** for that **Turn** immediately
- A **Player** who leaves during a **Game** stops participating and the **Game** continues with the remaining players
- A **Player** who leaves during a **Game** remains part of that **Game**'s final results
- A **Player** who is absent is not eligible to become the **Drawer**
- A disconnected **Player** who returns to a **Room** reclaims the same **Player** identity
- If the **Drawer** disconnects during a **Turn**, that **Turn** ends immediately
- If the **Drawer** disconnects during a **Turn**, that **Turn** awards no **Score**
- If a **Guesser** disconnects during a **Turn**, that **Turn** continues and the **Guesser** may resume participating if they return before it ends
- A **Game** belongs to exactly one **Room**
- A **Game** uses exactly one **Game mode**
- A **Game** has exactly one set of **Game settings**
- A **Game mode** defines its own **Minimum player count**
- A **Game** finishes early if active players fall below that **Game mode**'s **Minimum player count**
- A **Score** belongs to exactly one **Player** within exactly one **Game**
- A **Game** contains one or more **Rounds**
- A **Turn** belongs to exactly one **Game**
- A **Word** belongs to exactly one **Turn**
- A **Turn** may present **Word choices** to its **Drawer**
- A **Word choice** happens within a **Turn** before drawing begins
- A **Drawing** belongs to exactly one **Turn**
- A **Drawing** is created by exactly one **Drawer**
- A **Drawing** belongs to exactly one **Game**
- A **Player** may create multiple **Drawings** within one **Game**
- A completed **Turn** produces exactly one **Drawing**, even if the drawer leaves the canvas blank
- An interrupted **Turn** produces a **Drawing** from the drawer's partial work
- An interrupted **Word choice** does not produce a **Drawing**
- A **Drawing** remains part of its **Game** even if its **Drawer** leaves before the **Game** ends
- A **Turn** has exactly one **Drawer**
- A **Round** contains one or more **Turns**
- A **Player** is a **Guesser** during any **Turn** where they are not the **Drawer**

## Example dialogue

> **Dev:** "If a **Player** leaves during a **Game**, should their **Drawings** disappear from final results?"
> **Domain expert:** "No — their **Drawings** and **Score** remain part of that **Game**, but they are skipped as a future **Drawer** while absent."

## Flagged ambiguities

- `room_id` and **Room code** refer to the same concept at different layers — resolved: **Room code** is the product term, `room_id` is an internal implementation name.
- "Room name" was used in the UI for **Room code** — resolved: use **Room code** consistently.
- Room lifetime was unclear — resolved: a **Room** is ephemeral.
- The code currently conflates **Room** and **Game** — resolved in language: a **Room** is the player container; a **Game** is the playable session inside it.
- The current implementation behaves like one room equals one game lifecycle — resolved in language: a **Room** may host multiple **Games** over time, even though that is not implemented yet.
- Future ruleset variation was implicit — resolved: **Game mode** is a first-class term.
- Round count and turn length currently look like room-level values in parts of the UI — resolved: they are **Game settings**, and some game modes may not use them at all.
- A **Room** is not permanently tied to one **Game mode** — resolved: mode selection belongs to starting a **Game**, even though only one mode exists today.
- "between rounds" was used when discussing changing **Game mode** — resolved: **Game mode** changes between **Games**, not within a single **Game**.
- Player continuity was unclear — resolved: a **Player** keeps a stable identity within a **Room** across multiple **Games**.
- Score lifetime was unclear — resolved: **Score** is scoped to a single **Game** and resets for the next one.
- Host scope was unclear — resolved: **Host** is a room-level role and transfers when the host leaves.
- The code currently uses `:lobby` as part of the game lifecycle — resolved in language: **Lobby** is a room state before any **Game** starts.
- Lobby authority was unclear — resolved: only the **Host** chooses the next **Game mode** and **Game settings**.
- Room membership versus game participation was unclear — resolved: all current room members participate in the active **Game**.
- Late join behavior was unclear — resolved: a player who joins during an active **Game** enters that **Game** immediately.
- Mid-game turn eligibility was unclear — resolved: a player who joins during a **Round** can still draw later in that same **Round**.
- "earlier round" was used when discussing a mid-round join — resolved: the missed scoring opportunity is from earlier **Turns** in the current **Round**.
- Mid-turn join behavior was unclear — resolved: a player who joins during an active **Turn** can guess immediately.
- Leave behavior was unclear — resolved: when a **Player** leaves during a **Game**, the **Game** continues with the remaining players.
- Departed player final result behavior was unclear — resolved: a **Player** who leaves during a **Game** remains part of that **Game**'s final results.
- Absent player turn eligibility was unclear — resolved: an absent **Player** is skipped when choosing future **Drawers**.
- Not-enough-players behavior was unclear — resolved: if active players fall below the **Game mode** minimum after a **Game** has started, the **Game** finishes early and shows final results.
- The current drawing mode's minimum player count was informal — resolved: its **Minimum player count** is 2.
- Reconnection identity was unclear — resolved: a disconnected **Player** reclaims the same identity on return.
- Drawer disconnect behavior was unclear — resolved: the active **Turn** ends immediately, preserves its **Drawing**, and awards no **Score**.
- Guesser disconnect behavior was unclear — resolved: the active **Turn** continues, and a returning **Guesser** may still guess in that same **Turn** if it is still active.
- Word lifetime was unclear — resolved: a **Word** is scoped to a single **Turn**.
- Word selection authority was unclear — resolved: the **Drawer** chooses from **Word choices** provided by the game.
- Word choice importance was unclear — resolved: **Word choice** is a first-class step within a **Turn**.
- "pictures" was used for game-end showcase content — resolved: the domain term is **Drawing**.
- Blank drawing behavior was unclear — resolved: a completed **Turn** produces a **Drawing** even if the drawer leaves the canvas blank.
- Interrupted turn drawing behavior was unclear — resolved: an interrupted **Turn** produces a **Drawing** from the drawer's partial work.
- Interrupted word choice drawing behavior was unclear — resolved: an interrupted **Word choice** does not produce a **Drawing**.
- Drawing lifetime was unclear — resolved: a **Drawing** is scoped to a single **Game** and is not kept for later **Games** in the same **Room**.
- Departed drawer drawing behavior was unclear — resolved: a **Drawing** remains part of its **Game** if its **Drawer** leaves before the **Game** ends.
