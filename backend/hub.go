package main

import (
	"encoding/json"
	"log"
	"sync"
)

// Hub maintains the set of active players and games and broadcasts messages.
type Hub struct {
	Players       map[string]*Player // Registered players (Player ID -> Player)
	WaitingPlayer *Player            // Player waiting for an opponent (only one for 2-player games)
	Games         map[string]*Game   // Active games (Game ID -> Game)
	Register      chan *Player       // Channel for players to register
	Unregister    chan *Player       // Channel for players to unregister
	mu            sync.Mutex         // Mutex to protect concurrent access to Players, WaitingPlayer, Games maps
}

// NewHub creates and returns a new Hub instance.
func NewHub() *Hub {
	return &Hub{
		Players:    make(map[string]*Player),
		Games:      make(map[string]*Game),
		Register:   make(chan *Player),
		Unregister: make(chan *Player),
		// mu is automatically initialized
	}
}

// Run starts the Hub's main loop, listening on its channels.
// This should be run in a separate goroutine.
func (h *Hub) Run() {
	log.Println("Hub running...")
	for {
		select {
		// Handle player registration requests
		case player := <-h.Register:
			h.RegisterPlayer(player)

		// Handle player unregistration requests
		case player := <-h.Unregister:
			h.UnregisterPlayer(player)
		}
	}
}

// RegisterPlayer adds a new player to the hub and attempts to pair them.
func (h *Hub) RegisterPlayer(player *Player) {
	h.mu.Lock() // Lock hub state for modification
	defer h.mu.Unlock()

	h.Players[player.ID] = player // Add to the main player map
	log.Printf("Hub: Player %s registered. Total players: %d", player.ID, len(h.Players))

	// Attempt to pair the new player
	if h.WaitingPlayer == nil {
		// No one is waiting, this player becomes the waiting player
		h.WaitingPlayer = player
		log.Printf("Hub: Player %s is now waiting.", player.ID)
		// Send a 'waiting' message back to the player
		waitPayload := GameStatePayload{State: "waiting"}
		waitMsgBytes := mustMarshal(Message{Type: MsgTypeWaiting, Payload: json.RawMessage(mustMarshal(waitPayload))})
		// Non-blocking send
		select {
		case player.Send <- waitMsgBytes:
		default:
			log.Printf("Hub: Player %s send channel closed/full on waiting message.", player.ID)
		}

	} else {
		// Another player is waiting, pair them up and start a game
		opponent := h.WaitingPlayer
		h.WaitingPlayer = nil // Clear the waiting spot

		log.Printf("Hub: Pairing player %s with waiting player %s", player.ID, opponent.ID)
		// Create a new game instance (NewGame handles assigning players to the game)
		game := NewGame(h, opponent, player)
		h.Games[game.ID] = game // Add the new game to the active games map
		log.Printf("Hub: Game %s started. Active games: %d", game.ID, len(h.Games))
	}
}

// RegisterWaiting is called when a player leaves a game (e.g., opponent disconnects)
// and needs to be put back into the waiting pool.
func (h *Hub) RegisterWaiting(player *Player) {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Ensure player is still registered in the main map
	if _, ok := h.Players[player.ID]; !ok {
		log.Printf("Hub: Attempted to register disconnected player %s as waiting.", player.ID)
		return
	}

	// Reset player's game reference just in case
	player.Game = nil

	// Check if someone else is already waiting
	if h.WaitingPlayer == nil {
		h.WaitingPlayer = player
		log.Printf("Hub: Player %s (returned from game) is now waiting.", player.ID)
		// Send waiting message
		waitPayload := GameStatePayload{State: "waiting"}
		waitMsgBytes := mustMarshal(Message{Type: MsgTypeWaiting, Payload: json.RawMessage(mustMarshal(waitPayload))})
		select {
		case player.Send <- waitMsgBytes:
		default:
			log.Printf("Hub: Player %s send channel closed/full on re-waiting message.", player.ID)
		}
	} else {
		// This scenario (two players finishing games simultaneously needing to wait)
		// is less likely with the current 2-player setup but handle defensively.
		// Pair them immediately.
		opponent := h.WaitingPlayer
		h.WaitingPlayer = nil
		log.Printf("Hub: Pairing player %s with waiting player %s (immediately after game end)", player.ID, opponent.ID)
		game := NewGame(h, opponent, player)
		h.Games[game.ID] = game
		log.Printf("Hub: Game %s started (immediately after game end). Active games: %d", game.ID, len(h.Games))
	}
}

// UnregisterPlayer removes a player from the hub and closes their send channel.
func (h *Hub) UnregisterPlayer(player *Player) {
	h.mu.Lock() // Lock hub state for modification
	defer h.mu.Unlock()

	// Check if the player exists in the main map
	if _, ok := h.Players[player.ID]; ok {
		delete(h.Players, player.ID) // Remove from the map
		close(player.Send)           // Close the send channel to stop the writePump
		log.Printf("Hub: Player %s unregistered. Total players: %d", player.ID, len(h.Players))

		// If this player was the one waiting, clear the waiting spot
		if h.WaitingPlayer == player {
			h.WaitingPlayer = nil
			log.Printf("Hub: Player %s was waiting and has been removed.", player.ID)
		}
		// Game cleanup for the player is handled by the Player's readPump defer calling Game.HandleDisconnect
	} else {
		log.Printf("Hub: Attempted to unregister player %s who was not found.", player.ID)
	}
}

// HandleMessage routes incoming messages from players.
// If the player is in a game, it delegates to the game's handler.
func (h *Hub) HandleMessage(player *Player, msg Message) {
	// Check if the player is associated with a game
	// Reading player.Game requires care if Game can be modified concurrently.
	// A lock might be needed here, or ensure Game assignment is atomic/synchronized.
	// For simplicity here, assume Game reference check is safe enough or handled by caller context.
	game := player.Game // Get the game reference (might be nil)

	if game != nil {
		// Delegate message handling to the specific game instance
		game.HandleMessage(player, msg)
	} else {
		// Handle messages for players not currently in a game (e.g., in a lobby)
		// In this simple version, there are no lobby messages.
		log.Printf("Hub: Received message type '%s' from player %s (not in game)", msg.Type, player.ID)
		player.SendError("You are not currently in a game.")
	}
}

// EndGame removes a game from the Hub's active games map.
// This is typically called by the Game itself when it concludes.
func (h *Hub) EndGame(gameID string) {
	h.mu.Lock() // Lock hub state for modification
	defer h.mu.Unlock()

	if game, ok := h.Games[gameID]; ok {
		log.Printf("Hub: Ending game %s", gameID)
		// Optionally reset player game references here as well, although Game.HandleDisconnect should do it.
		for _, p := range game.Players {
			// Check if player still exists in hub before accessing
			if hubPlayer, playerExists := h.Players[p.ID]; playerExists {
				hubPlayer.Game = nil // Ensure player's game ref is cleared
				// Decide if players automatically go back to waiting after game ends normally
				h.RegisterWaiting(hubPlayer) // Example: put players back in queue
			}
		}
		delete(h.Games, gameID) // Remove the game from the active map
		log.Printf("Hub: Game %s removed. Active games: %d", gameID, len(h.Games))
	} else {
		log.Printf("Hub: Attempted to end game %s which was not found.", gameID)
	}
}
