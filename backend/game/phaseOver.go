package game

import (
	"backend/messages"
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
		GamePhase: p.Phase().String(),
		Players:   gs.getPlayerInfoList(),
	}

	log.Printf("GameState: Broadcasting GameFinished message with %d players.", len(finalScoresPayload.Players))
	go gs.Broadcaster.Broadcast(messages.GameFinishedResponse, finalScoresPayload)
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	log.Printf("GameState: Ignoring message type %s from player %s in GameOver phase.", msg.Type, player.Name)
	return p
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
