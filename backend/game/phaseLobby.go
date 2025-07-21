package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"time"
)

type WaitingInLobbyHandler struct{}

func (p *WaitingInLobbyHandler) Phase() GamePhase {
	return GamePhaseWaitingInLobby
}

func (p *WaitingInLobbyHandler) StartPhase(gs *GameState) {
	return
}

func (p *WaitingInLobbyHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type != messages.ClientStartGame || player.Id != gs.HostId || gs.IsActive {
		return p
	}

	if len(gs.Players) < minPlayersToStart {
		gs.BroadcastSystemMessage("Game start aborted, not enough players.")
		return p
	}

	var startGamePayload messages.StartGamePayload
	if err := json.Unmarshal(msg.Payload, &startGamePayload); err != nil {
		log.Printf("Error parsing startGame payload: %v", err)
		return p
	}

	// Validate round count is within acceptable range
	if startGamePayload.RoundCount < 1 || startGamePayload.RoundCount > 5 {
		startGamePayload.RoundCount = 3
	}

	if startGamePayload.RoundLength < 30 {
		startGamePayload.RoundLength = 30
	}

	gs.TotalRounds = startGamePayload.RoundCount
	gs.RoundDuration = time.Duration(startGamePayload.RoundLength) * time.Second
	gs.IsActive = true
	log.Printf("GameState: Starting game with %d rounds", gs.TotalRounds)
	return ackPhaseTransitionTo(&RoundSetupHandler{WordToPickFrom: nil})
}

func (p *WaitingInLobbyHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
