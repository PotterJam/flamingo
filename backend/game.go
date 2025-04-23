package main

import (
	"encoding/json"
	"github.com/google/uuid"
	"log"
	"math/rand"
	"sync"
)

// Game represents a single game session between two players.
type Game struct {
	ID      string
	Players map[string]*Player // Map Player ID to Player struct for quick lookup
	Drawer  *Player            // The player currently drawing
	Guesser *Player            // The player currently guessing
	Word    string             // The secret word for this game
	Hub     *Hub               // Reference back to the hub
	mu      sync.Mutex         // Mutex to protect concurrent access to game state
}

// NewGame creates and initializes a new game instance.
func NewGame(hub *Hub, player1 *Player, player2 *Player) *Game {
	game := &Game{
		ID:      uuid.NewString(), // Generate unique ID for the game
		Players: make(map[string]*Player),
		Hub:     hub,
		// mu is automatically initialized
	}
	// Add players to the game and set their Game reference
	game.Players[player1.ID] = player1
	game.Players[player2.ID] = player2
	player1.Game = game
	player2.Game = game

	log.Printf("Starting new game %s between %s and %s", game.ID, player1.ID, player2.ID)
	// Start the game logic (assign roles, select word)
	game.Start()
	return game
}

// Start sets up the game by selecting a word and assigning roles.
func (g *Game) Start() {
	g.mu.Lock()         // Lock the game state for modification
	defer g.mu.Unlock() // Ensure unlock happens even on panic

	// 1. Select Word
	if len(words) == 0 {
		log.Printf("Game %s: Error - Word list is empty!", g.ID)
		g.Word = "default" // Assign a default word or handle error appropriately
	} else {
		g.Word = words[rand.Intn(len(words))]
	}
	log.Printf("Game %s: Selected word: %s", g.ID, g.Word)

	// 2. Assign Roles randomly
	players := make([]*Player, 0, len(g.Players))
	for _, p := range g.Players {
		players = append(players, p)
	}
	// Simple random assignment
	if rand.Intn(2) == 0 {
		g.Drawer = players[0]
		g.Guesser = players[1]
	} else {
		g.Drawer = players[1]
		g.Guesser = players[0]
	}

	log.Printf("Game %s: Drawer: %s, Guesser: %s", g.ID, g.Drawer.ID, g.Guesser.ID)

	// 3. Send role assignment messages to each player
	drawerPayload := AssignRolePayload{Role: "drawer", Word: g.Word}
	drawerMsgBytes := mustMarshal(Message{Type: MsgTypeAssignRole, Payload: json.RawMessage(mustMarshal(drawerPayload))})
	// Use non-blocking send
	select {
	case g.Drawer.Send <- drawerMsgBytes:
	default:
		log.Printf("Game %s: Drawer %s send channel closed/full on start.", g.ID, g.Drawer.ID)
	}

	guesserPayload := AssignRolePayload{Role: "guesser", WordLength: len(g.Word)}
	guesserMsgBytes := mustMarshal(Message{Type: MsgTypeAssignRole, Payload: json.RawMessage(mustMarshal(guesserPayload))})
	// Use non-blocking send
	select {
	case g.Guesser.Send <- guesserMsgBytes:
	default:
		log.Printf("Game %s: Guesser %s send channel closed/full on start.", g.ID, g.Guesser.ID)
	}

	// 4. Optionally send a general Game Start message
	// startPayload := GameStatePayload{State: "active"}
	// startMsg, _ := json.Marshal(Message{Type: MsgTypeGameStart, Payload: json.RawMessage(mustMarshal(startPayload))})
	// g.Broadcast(startMsg) // Broadcast might be complex here due to locking, direct send is simpler
}

// Broadcast sends a message to all players currently in the game.
// NOTE: Be cautious with locking if calling this from methods already holding the lock.
func (g *Game) Broadcast(message []byte) {
	g.mu.Lock() // Lock to safely iterate over players map
	defer g.mu.Unlock()
	for id, player := range g.Players {
		select {
		case player.Send <- message:
			// Message queued successfully
		default:
			// Handle case where send buffer is full or channel is closed
			log.Printf("Game %s: Player %s send buffer full/closed on broadcast, closing channel.", g.ID, id)
			close(player.Send)    // Close the channel
			delete(g.Players, id) // Remove player from game map if channel closed
			// Optionally notify the hub or other players about this forced removal
		}
	}
}

// HandleMessage processes messages relevant to an active game state.
func (g *Game) HandleMessage(sender *Player, msg Message) {
	switch msg.Type {
	case MsgTypeDrawEvent:
		g.HandleDrawEvent(sender, msg.Payload)
	case MsgTypeGuess:
		g.HandleGuess(sender, msg.Payload)
	// Add other game-specific message handlers here (e.g., clear canvas)
	// case MsgTypeClearCanvas:
	// 	g.HandleClearCanvas(sender)
	default:
		log.Printf("Game %s: Received unhandled message type '%s' from player %s", g.ID, msg.Type, sender.ID)
	}
}

// HandleDrawEvent processes drawing data from the drawer and forwards it to the guesser.
func (g *Game) HandleDrawEvent(sender *Player, payload json.RawMessage) {
	g.mu.Lock() // Lock needed to check role and access guesser
	isDrawer := g.Drawer != nil && sender.ID == g.Drawer.ID
	guesser := g.Guesser // Get guesser reference while holding lock
	g.mu.Unlock()        // Unlock after reading required state

	if !isDrawer {
		log.Printf("Game %s: Player %s (not drawer) attempted to send DrawEvent.", g.ID, sender.ID)
		sender.SendError("Only the drawer can send drawing events.")
		return
	}

	if guesser == nil {
		log.Printf("Game %s: Drawer %s sent DrawEvent, but guesser is nil.", g.ID, sender.ID)
		return // Guesser might have disconnected
	}

	// Create the message to forward (reuse the original payload)
	drawMsgBytes := mustMarshal(Message{Type: MsgTypeDrawEvent, Payload: payload})

	// Send the draw event ONLY to the guesser (non-blocking)
	select {
	case guesser.Send <- drawMsgBytes:
		// Sent successfully
	default:
		log.Printf("Game %s: Guesser %s send buffer full/closed while forwarding DrawEvent.", g.ID, guesser.ID)
		// Guesser might have disconnected concurrently, cleanup handled elsewhere
	}
}

// HandleGuess processes a guess attempt from the guesser.
func (g *Game) HandleGuess(sender *Player, payload json.RawMessage) {
	g.mu.Lock() // Lock needed to check role and access word
	isGuesser := g.Guesser != nil && sender.ID == g.Guesser.ID
	correctWord := g.Word
	gameID := g.ID // Copy game ID for logging after unlock
	g.mu.Unlock()  // Unlock after reading required state

	if !isGuesser {
		log.Printf("Game %s: Player %s (not guesser) attempted to send Guess.", gameID, sender.ID)
		sender.SendError("Only the guesser can send guesses.")
		return
	}

	// Unmarshal the guess payload
	var guessPayload GuessPayload
	if err := json.Unmarshal(payload, &guessPayload); err != nil {
		log.Printf("Game %s: Error unmarshalling guess payload from %s: %v", gameID, sender.ID, err)
		sender.SendError("Invalid guess format.")
		return
	}

	log.Printf("Game %s: Received guess '%s' from guesser %s", gameID, guessPayload.Guess, sender.ID)

	// Check if the guess is correct (case-insensitive comparison is often good)
	// correct := strings.EqualFold(guessPayload.Guess, correctWord)
	correct := guessPayload.Guess == correctWord // Case-sensitive for now

	if correct {
		log.Printf("Game %s: Guess '%s' is CORRECT!", gameID, guessPayload.Guess)
		// --- Game Over Logic ---
		gameOverPayload := GuessResultPayload{Correct: true, Word: correctWord}
		gameOverMsgBytes := mustMarshal(Message{Type: MsgTypeGameOver, Payload: json.RawMessage(mustMarshal(gameOverPayload))})
		// Need to broadcast this to both players
		g.Broadcast(gameOverMsgBytes) // Broadcast handles locking internally

		// Signal the Hub to end/clean up this game
		g.Hub.EndGame(gameID)

	} else {
		log.Printf("Game %s: Guess '%s' is incorrect.", gameID, guessPayload.Guess)
		// Send incorrect guess feedback ONLY back to the guesser
		resultPayload := GuessResultPayload{Correct: false, Guess: guessPayload.Guess}
		resultMsgBytes := mustMarshal(Message{Type: MsgTypeGuessResult, Payload: json.RawMessage(mustMarshal(resultPayload))})
		// Non-blocking send
		select {
		case sender.Send <- resultMsgBytes:
		default:
			log.Printf("Game %s: Guesser %s send channel closed/full on incorrect guess result.", gameID, sender.ID)
		}

		// Optional: Broadcast the incorrect guess text to both players like a chat message
		// broadcastGuessPayload := map[string]string{"text": sender.ID + ": " + guessPayload.Guess}
		// broadcastGuessMsgBytes := mustMarshal(Message{Type: "chatMessage", Payload: json.RawMessage(mustMarshal(broadcastGuessPayload))})
		// g.Broadcast(broadcastGuessMsgBytes)
	}
}

// HandleDisconnect is called by a Player's readPump defer when they disconnect.
// It notifies the remaining player and triggers game cleanup via the Hub.
func (g *Game) HandleDisconnect(disconnectedPlayer *Player) {
	g.mu.Lock() // Lock to modify player map and access remaining player
	defer g.mu.Unlock()

	log.Printf("Game %s: Handling disconnect for player %s.", g.ID, disconnectedPlayer.ID)

	// Remove the disconnected player from the game's player map
	delete(g.Players, disconnectedPlayer.ID)

	// Find and notify the remaining player, if any
	var remainingPlayer *Player = nil
	for _, p := range g.Players {
		remainingPlayer = p
		break // Only one player left
	}

	if remainingPlayer != nil {
		log.Printf("Game %s: Notifying remaining player %s about disconnect.", g.ID, remainingPlayer.ID)
		// Send a specific message indicating opponent left
		leftPayload := PlayerLeftPayload{PlayerID: disconnectedPlayer.ID}
		leftMsgBytes := mustMarshal(Message{Type: MsgTypePlayerLeft, Payload: json.RawMessage(mustMarshal(leftPayload))})
		// Non-blocking send
		select {
		case remainingPlayer.Send <- leftMsgBytes:
		default:
			log.Printf("Game %s: Remaining player %s send channel closed/full on disconnect notification.", g.ID, remainingPlayer.ID)
		}

		// Reset the remaining player's game reference and put them back in the waiting pool via the Hub
		remainingPlayer.Game = nil
		// Use a non-blocking send to the Hub's channel or a dedicated method
		g.Hub.RegisterWaiting(remainingPlayer) // Assuming Hub handles potential blocking
	} else {
		log.Printf("Game %s: No remaining players after disconnect of %s.", g.ID, disconnectedPlayer.ID)
	}

	// Regardless of remaining players, tell the Hub to remove this game instance
	g.Hub.EndGame(g.ID) // Hub handles removing the game from its active map
}
