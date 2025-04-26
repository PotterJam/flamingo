package main

import (
	"log"
	"sync"
)

// Room maintains the set of players connected to the server and the game(s)
type Room struct {
	Players     map[string]*Player // Registered players (Player ID -> Player) - Connection tracking
	Game        *Game              // The single shared game instance
	Register    chan *Player
	Unregister  chan *Player
	PlayerReady chan *Player
	mu          sync.Mutex // Mutex to protect concurrent access to Players map
}

func NewRoom() *Room {
	room := &Room{
		Players:     make(map[string]*Player),
		Register:    make(chan *Player),
		Unregister:  make(chan *Player),
		PlayerReady: make(chan *Player),
	}
	room.Game = NewGame(room)
	log.Println("Room created and initialized shared game.")
	return room
}

// Run starts the Room's main loop, listening on its channels.
func (room *Room) Run() {
	log.Println("Room running...")
	for {
		select {
		case player := <-room.Register:
			room.mu.Lock()
			room.Players[player.ID] = player
			log.Printf("Room: Player %s connection registered. Total tracked: %d. Waiting for name.", player.ID, len(room.Players))
			room.mu.Unlock()

		case player := <-room.Unregister:
			room.mu.Lock()
			var playerToRemove *Player
			if existingPlayer, ok := room.Players[player.ID]; ok {
				delete(room.Players, player.ID)
				select {
				case <-existingPlayer.Send:
				default:
					close(existingPlayer.Send)
				}
				log.Printf("Room: Player %s (%s) connection unregistered. Total tracked: %d", player.ID, LogName(existingPlayer.Name), len(room.Players))
				playerToRemove = existingPlayer
			} else {
				log.Printf("Room: Player %s (%s) already unregistered from Room map.", player.ID, *player.Name)
			}
			room.mu.Unlock()

			if playerToRemove != nil {
				room.Game.RemovePlayer(playerToRemove)
			}

		case player := <-room.PlayerReady:
			log.Printf("Room: Received PlayerReady signal for %s (%s). Adding to game.", player.ID, *player.Name)
			room.Game.PlayerIsReady(player)
		}
	}
}

func (r *Room) HandleMessage(player *Player, msg Message) {
	// TODO: when implementing rooms (the spokes of the hub), we'll need to direct you to the right game here
	r.Game.HandleMessage(player, msg)
}

func (h *Room) Broadcast(message []byte) {
	h.mu.Lock()
	playersToSend := make([]*Player, 0, len(h.Players))
	for _, player := range h.Players {
		if player != nil {
			playersToSend = append(playersToSend, player)
		}
	}
	h.mu.Unlock()

	for _, p := range playersToSend {
		go func() {
			if p == nil {
				return
			}
			select {
			case p.Send <- message:
			default:
				log.Printf("Room Broadcast Warn: Player %s (%s) send buffer full/closed.", p.ID, *p.Name)
			}
		}()
	}
}

func (r *Room) BroadcastToPlayers(message []byte, players []*Player) {
	for _, p := range players {
		go func() {
			select {
			case p.Send <- message:
			default:
				log.Printf("Room BroadcastToPlayers Warn: Player %s (%s) send buffer full/closed.", p.ID, *p.Name)
			}
		}()
	}
}
