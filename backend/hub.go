package main // Already declared

import (
	"log"  // Needed here
	"sync" // Needed here
	// No websocket import needed here
)

// Hub maintains the set of active players and the single game instance.
type Hub struct {
	Players     map[string]*Player // Registered players (Player ID -> Player) - Connection tracking
	Game        *Game              // The single shared game instance
	Register    chan *Player       // Channel for players to register connection
	Unregister  chan *Player       // Channel for players to unregister connection
	PlayerReady chan *Player       // Channel for players who have set their name
	mu          sync.Mutex         // Mutex to protect concurrent access to Players map
}

// NewHub creates and returns a new Hub instance.
func NewHub() *Hub {
	hub := &Hub{
		Players:     make(map[string]*Player),
		Register:    make(chan *Player),
		Unregister:  make(chan *Player),
		PlayerReady: make(chan *Player),
	}
	hub.Game = NewGame(hub) // Create the game instance
	log.Println("Hub created and initialized shared game.")
	return hub
}

// Run starts the Hub's main loop, listening on its channels.
func (h *Hub) Run() {
	log.Println("Hub running...")
	for {
		select {
		case player := <-h.Register:
			// Handle new WebSocket connection registration
			h.mu.Lock()
			h.Players[player.ID] = player // Track connection
			log.Printf("Hub: Player %s connection registered. Total tracked: %d. Waiting for name.", player.ID, len(h.Players))
			h.mu.Unlock()
			// --- REMOVED sendGameInfo from here ---

		case player := <-h.Unregister:
			// Handle player disconnection
			h.mu.Lock()
			var playerToRemove *Player
			if existingPlayer, ok := h.Players[player.ID]; ok {
				delete(h.Players, player.ID)
				select {
				case <-existingPlayer.Send:
				default:
					close(existingPlayer.Send)
				} // Close channel safely
				log.Printf("Hub: Player %s (%s) connection unregistered. Total tracked: %d", player.ID, existingPlayer.Name, len(h.Players))
				playerToRemove = existingPlayer
			} else {
				log.Printf("Hub: Player %s (%s) already unregistered from Hub map.", player.ID, player.Name)
			}
			h.mu.Unlock()

			if playerToRemove != nil {
				h.Game.RemovePlayer(playerToRemove) // Remove from game after releasing hub lock
			}

		case player := <-h.PlayerReady:
			// Handle player setting their name
			log.Printf("Hub: Received PlayerReady signal for %s (%s). Adding to game.", player.ID, player.Name)
			// Add player to the game instance now that name is set
			// Game.PlayerIsReady handles sending gameInfo and updates
			h.Game.PlayerIsReady(player)
		}
	}
}

// HandleMessage routes incoming messages (from players who have already set their name) to the game.
func (h *Hub) HandleMessage(player *Player, msg Message) {
	// Ignore setName messages reaching the Hub
	if msg.Type == MsgTypeSetName {
		log.Printf("Hub: Ignored unexpected '%s' message from player %s (%s)", msg.Type, player.ID, player.Name)
		return
	}
	// All other valid game-related messages are handled by the Game instance
	h.Game.HandleMessage(player, msg)
}

// Broadcast sends a message to all currently connected players in the Hub.
func (h *Hub) Broadcast(message []byte) {
	h.mu.Lock()
	playersToSend := make([]*Player, 0, len(h.Players))
	for _, player := range h.Players {
		if player != nil {
			playersToSend = append(playersToSend, player)
		}
	}
	h.mu.Unlock()

	for _, player := range playersToSend {
		p := player
		go func() {
			if p == nil {
				return
			}
			select {
			case p.Send <- message:
			default:
				log.Printf("Hub Broadcast Warn: Player %s (%s) send buffer full/closed.", p.ID, p.Name)
			}
		}()
	}
}

// BroadcastToPlayers sends a message to a specific list of players.
func (h *Hub) BroadcastToPlayers(message []byte, players []*Player) {
	for _, player := range players {
		p := player
		go func() {
			if p == nil {
				return
			}
			select {
			case p.Send <- message:
			default:
				log.Printf("Hub BroadcastToPlayers Warn: Player %s (%s) send buffer full/closed.", p.ID, p.Name)
			}
		}()
	}
}
