package main

import (
	"encoding/json"
	"log"
	"sync"
	"time"
)

// GameState represents the single, shared game session.
// TODO: move a bunch of this state into the phases.
type GameState struct {
	Players           []*Player
	HostId            string
	CurrentDrawerIdx  int                  // Index in Players slice of the current drawer (-1 if no game)
	Word              string               // The secret word for the current turn
	CorrectGuessTimes map[string]time.Time // player ID -> time they guessed correctly
	TurnStartTime     time.Time            // When the current turn (drawing phase) started
	// TODO: Replace reference to room with channel
	Room     *Room
	mu       sync.Mutex // Mutex to protect concurrent access to game state
	IsActive bool       // Flag indicating if a round/turn is currently running

	timerForTimeout *time.Timer
	turnEndTime     time.Time
}

func (g *GameState) broadcastPlayerUpdate() {
	payload := PlayerUpdatePayload{
		Players: g.getPlayerInfoList(), // Assumes lock held
		HostID:  g.HostId,
	}
	msgBytes := MustMarshal(Message{Type: PlayerUpdateResponse, Payload: json.RawMessage(MustMarshal(payload))})
	go g.Room.Broadcast(msgBytes)
}

func (g *GameState) BroadcastSystemMessage(message string) {
	payload := ChatPayload{SenderName: "System", Message: message, IsSystem: true}
	msgBytes := MustMarshal(Message{Type: ChatResponse, Payload: json.RawMessage(MustMarshal(payload))})
	go g.Room.Broadcast(msgBytes)
}

func (g *GameState) getPlayerInfoList() []PlayerInfo {
	infoList := make([]PlayerInfo, 0, len(g.Players))
	for _, p := range g.Players {
		if p != nil {
			_, hasGuessedCorrectly := g.CorrectGuessTimes[p.Id]
			infoList = append(infoList, PlayerInfo{
				ID:                  p.Id,
				Name:                p.Name,
				Score:               p.Score,
				IsHost:              p.Id == g.HostId,
				HasGuessedCorrectly: hasGuessedCorrectly,
			})
		} else {
			log.Printf("GameState Error: Found nil player in g.Players during getPlayerInfoList")
		}
	}
	return infoList
}

func (g *GameState) isDrawer(p *Player) bool {
	if !g.IsActive {
		return false
	}

	if g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}

	return g.Players[g.CurrentDrawerIdx].Id == p.Id
}
