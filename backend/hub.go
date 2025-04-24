package main

import (
	"log"
	"sync"
)

// Hub maintains the set of players connected to the server and the game(s)
type Hub struct {
	Players     map[string]*Player // Registered players (Player ID -> Player) - Connection tracking
	Game        *Game              // The single shared game instance
	Register    chan *Player
	Unregister  chan *Player
	PlayerReady chan *Player
	mu          sync.Mutex // Mutex to protect concurrent access to Players map
}

func NewHub() *Hub {
	hub := &Hub{
		Players:     make(map[string]*Player),
		Register:    make(chan *Player),
		Unregister:  make(chan *Player),
		PlayerReady: make(chan *Player),
	}
	hub.Game = NewGame(hub)
	log.Println("Hub created and initialized shared game.")
	return hub
}

// Run starts the Hub's main loop, listening on its channels.
func (h *Hub) Run() {
	log.Println("Hub running...")
	for {
		select {
		case player := <-h.Register:
			h.mu.Lock()
			h.Players[player.ID] = player
			log.Printf("Hub: Player %s connection registered. Total tracked: %d. Waiting for name.", player.ID, len(h.Players))
			h.mu.Unlock()

		case player := <-h.Unregister:
			h.mu.Lock()
			var playerToRemove *Player
			if existingPlayer, ok := h.Players[player.ID]; ok {
				delete(h.Players, player.ID)
				select {
				case <-existingPlayer.Send:
				default:
					close(existingPlayer.Send)
				}
				log.Printf("Hub: Player %s (%s) connection unregistered. Total tracked: %d", player.ID, existingPlayer.Name, len(h.Players))
				playerToRemove = existingPlayer
			} else {
				log.Printf("Hub: Player %s (%s) already unregistered from Hub map.", player.ID, player.Name)
			}
			h.mu.Unlock()

			if playerToRemove != nil {
				h.Game.RemovePlayer(playerToRemove)
			}

		case player := <-h.PlayerReady:
			log.Printf("Hub: Received PlayerReady signal for %s (%s). Adding to game.", player.ID, player.Name)
			h.Game.PlayerIsReady(player)
		}
	}
}

func (h *Hub) HandleMessage(player *Player, msg Message) {
	h.Game.HandleMessage(player, msg)
}

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
		go func() {
			if player == nil {
				return
			}
			select {
			case player.Send <- message:
			default:
				log.Printf("Hub Broadcast Warn: Player %s (%s) send buffer full/closed.", player.ID, player.Name)
			}
		}()
	}
}

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
