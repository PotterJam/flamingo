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
	go room.Game.HandleEvents()

	return room
}

// Room maintains the set of players playing the same game
type Room struct {
	Id          string
	Players     map[string]*Player // Registered players (Player Id -> Player) - Connection tracking
	Game        *Game
	Register    chan *Player
	Unregister  chan *Player
	PlayerReady chan *Player
	mu          sync.Mutex
}

func NewRoom() *Room {
	r := &Room{
		Id:          GenerateSlug(),
		Players:     make(map[string]*Player),
		Register:    make(chan *Player),
		Unregister:  make(chan *Player),
		PlayerReady: make(chan *Player),
	}
	r.Game = NewGame(r)
	log.Printf("{%s} Room created", r.Id)
	return r
}

// Run starts the Room's main loop, listening on its channels.
func (r *Room) Run() {
	log.Printf("{%s} Running", r.Id)

	for {
		select {
		case player := <-r.Register:
			r.mu.Lock()
			r.Players[player.Id] = player
			log.Printf("{%s} Player %s '%s' connection registered. Total tracked: %d", r.Id, player.Id, player.Name, len(r.Players))
			r.mu.Unlock()

		case player := <-r.Unregister:
			r.mu.Lock()
			var playerToRemove *Player
			if existingPlayer, ok := r.Players[player.Id]; ok {
				delete(r.Players, player.Id)
				close(existingPlayer.Send)
				log.Printf("{%s} Player %s (%s) connection unregistered. Total tracked: %d", r.Id, player.Id, existingPlayer.Name, len(r.Players))
				playerToRemove = existingPlayer
			} else {
				log.Printf("{%s} Player %s (%s) already unregistered from Room map", r.Id, player.Id, player.Name)
			}
			r.mu.Unlock()

			if playerToRemove != nil {
				// TODO: removing player needs to be handled better by the phases, somehow. Channel?
				r.Game.RemovePlayer(playerToRemove)
			}

		case playerToAdd := <-r.PlayerReady:
			log.Printf("{%s} Received PlayerReady signal for %s (%s). Adding to game", r.Id, playerToAdd.Id, playerToAdd.Name)
			r.Game.AddPlayer(playerToAdd)
		}
	}
}

func (r *Room) Broadcast(message []byte) {
	r.mu.Lock()
	// copy first to minimise time lock is held
	// I'm not convinced this is needed since spawning a go routine is very fast
	playersToSend := make([]*Player, 0, len(r.Players))
	for _, player := range r.Players {
		if player != nil {
			playersToSend = append(playersToSend, player)
		}
	}
	r.mu.Unlock()

	for _, p := range playersToSend {
		go func() {
			if p == nil {
				return
			}
			p.Send <- message
		}()
	}
}

func (r *Room) BroadcastToPlayers(message []byte, players []*Player) {
	for _, p := range players {
		go func() {
			p.Send <- message
		}()
	}
}
