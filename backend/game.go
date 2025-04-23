package main

import (
	"encoding/json" // Needed here
	"log"           // Needed here
	"math/rand"     // Needed here
	"sync"          // Needed here
	"time"          // Needed here
	// No websocket import needed here if Hub handles broadcast
)

const turnDuration = 60 * time.Second // 60 second timer for each turn
const minPlayersToStart = 2           // Minimum players needed to start/continue

// Game represents the single, shared game session.
type Game struct {
	Players          []*Player       // Ordered list of players who have set their name
	HostID           string          // ID of the player who is the host
	CurrentDrawerIdx int             // Index in Players slice of the current drawer (-1 if no game)
	Word             string          // The secret word for the current turn
	GuessedCorrectly map[string]bool // Set of player IDs who guessed correctly this turn
	Hub              *Hub            // Reference back to the hub
	mu               sync.Mutex      // Mutex to protect concurrent access to game state
	IsActive         bool            // Flag indicating if a round/turn is currently running
	turnTimer        *time.Timer     // Timer for the current turn
	turnEndTime      time.Time       // When the current turn is scheduled to end
}

// NewGame creates the shared game instance.
func NewGame(hub *Hub) *Game {
	log.Println("Game: Creating new shared game instance.")
	return &Game{
		Players:          make([]*Player, 0, 10),
		HostID:           "", // No host initially
		CurrentDrawerIdx: -1,
		GuessedCorrectly: make(map[string]bool),
		Hub:              hub,
		IsActive:         false,
	}
}

// PlayerIsReady adds a player who has set their name to the game list.
// Called by the Hub when it receives the PlayerReady signal.
func (g *Game) PlayerIsReady(player *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	// Avoid adding duplicates
	for _, p := range g.Players {
		if p.ID == player.ID {
			log.Printf("Game: Player %s (%s) already marked as ready.", player.ID, player.Name)
			g.sendGameInfo(player) // Send current state again
			return
		}
	}

	g.Players = append(g.Players, player)
	log.Printf("Game: Player %s (%s) marked ready. Total ready players: %d", player.ID, player.Name, len(g.Players))

	// Assign host if this is the first ready player
	if len(g.Players) == 1 {
		g.HostID = player.ID
		log.Printf("Game: Player %s (%s) assigned as Host.", player.ID, player.Name)
	}

	// Send current game state to the new player
	g.sendGameInfo(player) // Assumes lock is held

	// Broadcast updated player list and host ID to everyone
	g.broadcastPlayerUpdate() // Assumes lock is held

	// --- Game does NOT start automatically ---
	if len(g.Players) >= minPlayersToStart && g.HostID == player.ID {
		// Optional: Send a system message to the host that they can start
		// go player.SendMessage("systemHint", map[string]string{"message": "You are the host. Start the game when ready!"})
	}
}

// RemovePlayer removes a player from the game list.
func (g *Game) RemovePlayer(player *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	found := false
	playerIndex := -1
	for i, p := range g.Players {
		if p != nil && p.ID == player.ID { // Add nil check
			found = true
			playerIndex = i
			break
		}
	}

	if !found {
		log.Printf("Game: Attempted to remove player %s (%s) who was not found (or not ready).", player.ID, player.Name)
		return
	}

	// Remove player from slice
	g.Players = append(g.Players[:playerIndex], g.Players[playerIndex+1:]...)
	log.Printf("Game: Player %s (%s) removed. Remaining players: %d", player.ID, player.Name, len(g.Players))

	// Clean up guess status
	delete(g.GuessedCorrectly, player.ID)

	wasHost := g.HostID == player.ID
	wasDrawer := g.IsActive && g.CurrentDrawerIdx == playerIndex

	// Handle Host Leaving
	if wasHost {
		if len(g.Players) > 0 {
			// Assign the next player in the list as the new host
			g.HostID = g.Players[0].ID
			log.Printf("Game: Host %s (%s) left. New host assigned: %s (%s).", player.Name, player.ID, g.Players[0].Name, g.HostID)
		} else {
			g.HostID = ""
			log.Println("Game: Host left. No players remaining.")
		}
	}

	// Handle Game State
	if !g.IsActive {
		g.broadcastPlayerUpdate() // Includes new host if changed
		return
	}

	// If game was active:
	if len(g.Players) < minPlayersToStart {
		log.Println("Game: Player count dropped below minimum. Ending game.")
		g.endGame("Not enough players.")
		g.broadcastPlayerUpdate() // Includes new host if changed
	} else {
		// Adjust drawer index if necessary
		if playerIndex < g.CurrentDrawerIdx {
			g.CurrentDrawerIdx--
		} else if playerIndex == g.CurrentDrawerIdx && len(g.Players) > 0 {
			g.CurrentDrawerIdx = (playerIndex - 1 + len(g.Players)) % len(g.Players)
		}

		allGuessed := g.checkAllGuessed()
		g.broadcastPlayerUpdate() // Send update *before* potentially ending turn

		if wasDrawer || allGuessed {
			log.Printf("Game: Ending turn early due to player %s leaving (was drawer: %t, all guessed now: %t).", player.Name, wasDrawer, allGuessed)
			g.endTurn()
		}
	}
}

// startGame initializes the first turn. Called only by HandleStartGame. Assumes lock is held.
func (g *Game) startGame() {
	log.Println("Game: startGame() called.")
	if len(g.Players) < minPlayersToStart {
		log.Println("Game: startGame() aborted, less than minimum players.")
		return
	}
	if g.IsActive {
		log.Println("Game: startGame() aborted, game already active.")
		return
	}

	log.Println("Game: Setting IsActive=true and starting first turn.")
	g.IsActive = true
	g.CurrentDrawerIdx = -1
	g.nextTurn()
}

// endGame resets the game state (e.g., not enough players). Assumes lock is held.
func (g *Game) endGame(reason string) {
	log.Printf("Game: endGame() called. Reason: %s", reason)
	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}
	g.IsActive = false
	g.CurrentDrawerIdx = -1
	g.Word = ""
	g.GuessedCorrectly = make(map[string]bool)
	g.turnEndTime = time.Time{}
	g.BroadcastSystemMessage("Game Over: " + reason)
}

// nextTurn selects next drawer, picks word, starts timer, notifies clients. Assumes lock is held.
func (g *Game) nextTurn() {
	log.Println("Game: nextTurn() called.")
	if !g.IsActive {
		log.Println("Game: nextTurn() called but game is not active. Aborting.")
		return
	}
	if len(g.Players) < minPlayersToStart {
		log.Println("Game: Cannot start next turn, less than minimum players.")
		g.endGame("Not enough players.")
		g.broadcastPlayerUpdate()
		return
	}

	if g.turnTimer != nil {
		g.turnTimer.Stop()
	}

	if g.CurrentDrawerIdx < -1 || g.CurrentDrawerIdx >= len(g.Players) {
		log.Printf("Game: Resetting invalid CurrentDrawerIdx (%d) before next turn.", g.CurrentDrawerIdx)
		g.CurrentDrawerIdx = -1
	}
	g.CurrentDrawerIdx = (g.CurrentDrawerIdx + 1) % len(g.Players)
	newDrawer := g.Players[g.CurrentDrawerIdx]

	g.Word = words[rand.Intn(len(words))]
	g.GuessedCorrectly = make(map[string]bool)

	g.turnEndTime = time.Now().Add(turnDuration)
	log.Printf("Game: Setting turn timer for %v.", turnDuration)
	g.turnTimer = time.AfterFunc(turnDuration, func() {
		log.Printf("Game: Turn timer expired callback initiated for drawer %s (%s), word '%s'", newDrawer.ID, newDrawer.Name, g.Word)
		g.mu.Lock()
		if g.IsActive && g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) && g.Players[g.CurrentDrawerIdx].ID == newDrawer.ID {
			log.Println("Game: Timer expired, calling endTurn().")
			g.endTurn()
		} else {
			log.Println("Game: Timer expired but state changed, ignoring timer.")
		}
		g.mu.Unlock()
	})

	log.Printf("Game: Starting turn. Drawer: %s (%s), Word: %s, Ends At: %v", newDrawer.ID, newDrawer.Name, g.Word, g.turnEndTime.Format(time.Kitchen))

	turnPayloadBase := TurnStartPayload{
		CurrentDrawerID: newDrawer.ID,
		WordLength:      len(g.Word),
		Players:         g.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     g.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = g.Word
	log.Printf("Game: Sending TurnStart (with word) to drawer %s", newDrawer.Name)
	go newDrawer.SendMessage(MsgTypeTurnStart, drawerPayload)

	guesserPayload := turnPayloadBase
	msgBytes := mustMarshal(Message{Type: MsgTypeTurnStart, Payload: json.RawMessage(mustMarshal(guesserPayload))})
	playersToSendTo := make([]*Player, 0, len(g.Players)-1)
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("Game: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go g.Hub.BroadcastToPlayers(msgBytes, playersToSendTo)

	g.BroadcastSystemMessage(newDrawer.Name + " is drawing!")
}

// endTurn is called when a turn finishes. Assumes lock is held.
func (g *Game) endTurn() {
	log.Println("Game: endTurn() called.")
	if !g.IsActive {
		log.Println("Game: Attempted to end turn, but game is not active.")
		return
	}

	log.Printf("Game: Ending turn for word '%s'.", g.Word)

	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}

	g.BroadcastSystemMessage("Turn over! The word was: " + g.Word)
	turnEndPayload := TurnEndPayload{CorrectWord: g.Word}
	turnEndMsgBytes := mustMarshal(Message{Type: MsgTypeTurnEnd, Payload: json.RawMessage(mustMarshal(turnEndPayload))})
	log.Println("Game: Broadcasting TurnEnd message.")
	go g.Hub.Broadcast(turnEndMsgBytes)

	log.Println("Game: Scheduling next turn.")
	time.AfterFunc(3*time.Second, func() {
		log.Println("Game: Delay finished, attempting to start next turn.")
		g.mu.Lock()
		if g.IsActive {
			g.nextTurn()
		} else {
			log.Println("Game: Game became inactive during turn delay, not starting next turn.")
		}
		g.mu.Unlock()
	})
}

// sendGameInfo sends the initial game state to a player. Assumes lock is held.
func (g *Game) sendGameInfo(player *Player) {
	payload := GameInfoPayload{
		YourID:       player.ID,
		Players:      g.getPlayerInfoList(), // Assumes lock held
		HostID:       g.HostID,
		IsGameActive: g.IsActive,
	}
	if g.IsActive && g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) {
		payload.CurrentDrawerID = g.Players[g.CurrentDrawerIdx].ID
		payload.WordLength = len(g.Word)
		payload.TurnEndTime = g.turnEndTime.UnixMilli()
		if player.ID == payload.CurrentDrawerID {
			payload.Word = g.Word
		}
	}
	log.Printf("Game: Sending game info to player %s (%s). Active: %t, Host: %s", player.ID, player.Name, payload.IsGameActive, g.HostID)
	go player.SendMessage(MsgTypeGameInfo, payload)
}

// HandleMessage processes messages relevant to the game state.
func (g *Game) HandleMessage(sender *Player, msg Message) {
	switch msg.Type {
	case MsgTypeDrawEvent:
		g.HandleDrawEvent(sender, msg.Payload)
	case MsgTypeGuess:
		g.HandleGuess(sender, msg.Payload)
	case MsgTypeStartGame: // New case for host starting game
		g.HandleStartGame(sender)
	default:
		// Ignore setName here explicitly as well, though Hub should catch it first
		if msg.Type != MsgTypeSetName {
			log.Printf("Game: Received unhandled message type '%s' from player %s (%s)", msg.Type, sender.ID, sender.Name)
		}
	}
}

// HandleStartGame allows the host to start the game.
func (g *Game) HandleStartGame(sender *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	log.Printf("Game: Received StartGame request from %s (%s)", sender.ID, sender.Name)

	if sender.ID != g.HostID {
		log.Printf("Game: StartGame denied. Player %s is not the host (%s).", sender.Name, g.HostID)
		sender.SendError("Only the host can start the game.")
		return
	}
	if g.IsActive {
		log.Println("Game: StartGame denied. Game is already active.")
		sender.SendError("The game is already in progress.")
		return
	}
	if len(g.Players) < minPlayersToStart {
		log.Printf("Game: StartGame denied. Not enough players (%d/%d).", len(g.Players), minPlayersToStart)
		sender.SendError("Not enough players to start the game (minimum " + string(minPlayersToStart+'0') + ").")
		return
	}

	log.Printf("Game: Host %s (%s) is starting the game.", sender.Name, sender.ID)
	g.startGame() // Assumes lock is held
}

// HandleDrawEvent processes drawing data and forwards it.
func (g *Game) HandleDrawEvent(sender *Player, payload json.RawMessage) {
	g.mu.Lock()
	isActive := g.IsActive
	isDrawer := isActive && g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) && g.Players[g.CurrentDrawerIdx].ID == sender.ID
	playersCopy := make([]*Player, 0, len(g.Players))
	if isActive {
		for _, p := range g.Players {
			playersCopy = append(playersCopy, p)
		}
	}
	g.mu.Unlock()

	if !isActive {
		return
	}
	if !isDrawer {
		sender.SendError("Only the current drawer can send drawing events.")
		return
	}

	// Use the correct constant for broadcasting draw events
	drawMsgBytes := mustMarshal(Message{Type: MsgTypeDrawEventBroadcast, Payload: payload})
	playersToSendTo := make([]*Player, 0, len(playersCopy)-1)
	for _, p := range playersCopy {
		if p != nil && p.ID != sender.ID {
			playersToSendTo = append(playersToSendTo, p)
		}
	} // Add nil check
	go g.Hub.BroadcastToPlayers(drawMsgBytes, playersToSendTo)
}

// HandleGuess processes a guess attempt.
func (g *Game) HandleGuess(sender *Player, payload json.RawMessage) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if !g.IsActive {
		return
	}

	if g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) && g.Players[g.CurrentDrawerIdx].ID == sender.ID {
		sender.SendError("The drawer cannot make guesses.")
		return
	}
	if g.GuessedCorrectly[sender.ID] {
		sender.SendError("You already guessed the word correctly this turn.")
		return
	}

	var guessPayload GuessPayload
	if err := json.Unmarshal(payload, &guessPayload); err != nil {
		sender.SendError("Invalid guess format.")
		return
	}

	correct := guessPayload.Guess == g.Word

	if correct {
		log.Printf("Game: Guess '%s' by %s (%s) is CORRECT!", guessPayload.Guess, sender.Name, sender.ID)
		g.GuessedCorrectly[sender.ID] = true

		correctPayload := PlayerGuessedCorrectlyPayload{PlayerID: sender.ID}
		msgBytes := mustMarshal(Message{Type: MsgTypePlayerGuessedCorrectly, Payload: json.RawMessage(mustMarshal(correctPayload))})
		go g.Hub.Broadcast(msgBytes)

		if g.checkAllGuessed() {
			log.Println("Game: All players have guessed correctly.")
			g.endTurn() // Assumes lock held
		}
	} else {
		g.BroadcastChatMessage(sender.Name, guessPayload.Guess) // Assumes lock held
	}
}

// checkAllGuessed checks if all non-drawer players have guessed correctly. Assumes lock is held.
func (g *Game) checkAllGuessed() bool {
	if !g.IsActive || len(g.Players) < minPlayersToStart || g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}
	totalPlayers := len(g.Players)
	correctCount := 0
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx && g.GuessedCorrectly[p.ID] {
			correctCount++
		}
	}
	requiredCorrect := totalPlayers - 1
	if requiredCorrect < 0 {
		requiredCorrect = 0
	}
	return correctCount == requiredCorrect
}

// --- Broadcasting Helpers (Assume lock is held when called, but broadcast via Hub) ---

// broadcastPlayerUpdate sends the current player list and host ID.
func (g *Game) broadcastPlayerUpdate() {
	payload := PlayerUpdatePayload{
		Players: g.getPlayerInfoList(), // Assumes lock held
		HostID:  g.HostID,
	}
	msgBytes := mustMarshal(Message{Type: MsgTypePlayerUpdate, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

// BroadcastChatMessage sends an incorrect guess or system message.
func (g *Game) BroadcastChatMessage(senderName, message string) {
	payload := ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	msgBytes := mustMarshal(Message{Type: MsgTypeChat, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

// BroadcastSystemMessage sends a system message.
func (g *Game) BroadcastSystemMessage(message string) {
	payload := ChatPayload{SenderName: "System", Message: message, IsSystem: true}
	msgBytes := mustMarshal(Message{Type: MsgTypeChat, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

// getPlayerInfoList creates PlayerInfo list, including host and guess status. Assumes lock is held.
func (g *Game) getPlayerInfoList() []PlayerInfo {
	infoList := make([]PlayerInfo, 0, len(g.Players)) // Initialize with 0 length
	for _, p := range g.Players {
		if p != nil {
			infoList = append(infoList, PlayerInfo{ // Append valid players
				ID:                  p.ID,
				Name:                p.Name,
				IsHost:              p.ID == g.HostID,
				HasGuessedCorrectly: g.GuessedCorrectly[p.ID],
			})
		} else {
			log.Printf("Game Error: Found nil player in g.Players during getPlayerInfoList")
		}
	}
	return infoList
}
