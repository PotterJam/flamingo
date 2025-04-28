package main

import (
	"log"
	"sync"
)

// Maintains the list of currently alive rooms
type RoomManager struct {
	rooms map[string]*Room
	mu    sync.Mutex
}

func NewRoomManager() *RoomManager {
	return &RoomManager{
		rooms: make(map[string]*Room),
	}
}

func (rm *RoomManager) GetRoom(roomId string) *Room {
	room, ok := rm.rooms[roomId]
	if !ok {
		return nil
	}
	return room
}

func (rm *RoomManager) Run() {
	log.Print("starting room manager")
}

func (rm *RoomManager) CreateRoom() *Room {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	room := NewRoom()
	rm.rooms[room.Id] = room

	go room.Run()

	return room
}

// Room maintains the set of players connected to the server and the game(s)
type Room struct {
	Id          string
	Players     map[string]*Player // Registered players (Player Id -> Player) - Connection tracking
	Game        *Game              // The single shared game instance
	Register    chan *Player
	Unregister  chan *Player
	PlayerReady chan *Player
	mu          sync.Mutex // Mutex to protect concurrent access to Players map
}

func NewRoom() *Room {
	room := &Room{
		Id:          GenerateSlug(),
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
			room.Players[player.Id] = player
			log.Printf("Room: Player %s connection registered. Total tracked: %d. Waiting for name.", player.Id, len(room.Players))
			room.mu.Unlock()

		case player := <-room.Unregister:
			room.mu.Lock()
			var playerToRemove *Player
			if existingPlayer, ok := room.Players[player.Id]; ok {
				delete(room.Players, player.Id)
				select {
				case <-existingPlayer.Send:
				default:
					close(existingPlayer.Send)
				}
				log.Printf("Room: Player %s (%s) connection unregistered. Total tracked: %d", player.Id, existingPlayer.Name, len(room.Players))
				playerToRemove = existingPlayer
			} else {
				log.Printf("Room: Player %s (%s) already unregistered from Room map.", player.Id, player.Name)
			}
			room.mu.Unlock()

			if playerToRemove != nil {
				// TODO: removing player needs to be handled better by the phases, somehow. Channel?
				room.Game.RemovePlayer(playerToRemove)
			}

		case playerToAdd := <-room.PlayerReady:
			log.Printf("Room: Received PlayerReady signal for %s (%s). Adding to game.", playerToAdd.Id, playerToAdd.Name)
			room.Game.AddPlayer(playerToAdd)
		}
	}
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
				log.Printf("Room Broadcast Warn: Player %s (%s) send buffer full/closed.", p.Id, p.Name)
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
				log.Printf("Room BroadcastToPlayers Warn: Player %s (%s) send buffer full/closed.", p.Id, p.Name)
			}
		}()
	}
}
