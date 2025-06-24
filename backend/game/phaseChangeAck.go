package game

import (
	"backend/messages"
	"encoding/json"
	"slices"
	"time"
)

type PhaseChangeHandler struct {
	HandlerToChangeTo GamePhaseHandler
	AckedPlayers      []string
}

func (p *PhaseChangeHandler) Phase() GamePhase {
	return GamePhaseChangeAck
}

func (p *PhaseChangeHandler) StartPhase(gs *GameState) {
	gs.timerForTimeout = time.NewTimer(3 * time.Second)

	ackPayload := messages.PhaseChangeAckPayload{
		NewPhase: p.HandlerToChangeTo.Phase().String(),
	}

	turnEndMsg := messages.Message{Type: messages.PhaseChangeAckResponse, Payload: json.RawMessage(messages.MustMarshal(ackPayload))}
	go gs.Broadcaster.Broadcast(turnEndMsg)

	return
}

func (p *PhaseChangeHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type == messages.ClientPhaseChangeAck && !slices.Contains(p.AckedPlayers, player.Id) {
		var payload messages.PhaseChangeAckPayload
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			player.SendError("Invalid phase change ack payload.")
		} else if payload.NewPhase != p.HandlerToChangeTo.Phase().String() {
			player.SendError("Sent the wrong phase in ack payload.")
		} else {
			p.AckedPlayers = append(p.AckedPlayers, player.Id)
		}
	}

	// Check if all current players have acknowledged - more robust than length comparison
	if p.allCurrentPlayersAcked(gs) {
		return p.HandlerToChangeTo
	}

	return p
}

func (p *PhaseChangeHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	// Identify and remove players who didn't acknowledge within the time limit
	playersToRemove := make([]*Player, 0)
	for _, player := range gs.Players {
		if !slices.Contains(p.AckedPlayers, player.Id) {
			playersToRemove = append(playersToRemove, player)
		}
	}

	for _, player := range playersToRemove {
		gs.BroadcastSystemMessage(player.Name + " was removed for not responding to phase change.")
		player.SendError("Removed from game for not acknowledging phase change in time.")

		go func(p *Player) {
			gs.PlayerOperations <- PlayerOperation{Type: PlayerOpRemove, Player: p}
		}(player)
	}

	// Continue with phase change. The players will be removed from GameState
	// shortly by the main game loop. The next phase should be resilient to this.
	return p.HandlerToChangeTo
}

func (p *PhaseChangeHandler) allCurrentPlayersAcked(gs *GameState) bool {
	for _, player := range gs.Players {
		if !slices.Contains(p.AckedPlayers, player.Id) {
			return false
		}
	}
	return true
}
