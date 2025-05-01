package game

import (
	"backend/messages"
	"encoding/json"
	"log"
)

type GameOverHandler struct{}

func (p *GameOverHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *GameOverHandler) StartPhase(gs *GameState) {
	log.Println("GameState: Entering GameOver phase.")
	gs.IsActive = false

	finalScoresPayload := messages.GameFinishedPayload{
		Players: gs.getPlayerInfoList(),
	}

	gameOverMsg := messages.Message{
		Type:    messages.GameFinishedResponse,
		Payload: json.RawMessage(messages.MustMarshal(finalScoresPayload)),
	}

	log.Printf("GameState: Broadcasting GameFinished message with %d players.", len(finalScoresPayload.Players))
	go gs.Broadcaster.Broadcast(gameOverMsg)
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	log.Printf("GameState: Ignoring message type %s from player %s in GameOver phase.", msg.Type, player.Name)
	return p
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
