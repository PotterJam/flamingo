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

	// Prepare drawing histories for each player - flatten to one entry per drawing
	drawingHistories := make([]messages.PlayerDrawingHistory, 0)
	for _, player := range gs.Players {
		if drawingRounds, exists := gs.PlayerDrawingHistories[player.Id]; exists && len(drawingRounds) > 0 {
			// Each round they drew becomes a separate PlayerDrawingHistory entry
			for roundIdx, drawings := range drawingRounds {
				drawingHistories = append(drawingHistories, messages.PlayerDrawingHistory{
					PlayerID:     player.Id,
					PlayerName:   player.Name,
					DrawingSteps: drawings,
				})
				log.Printf("GameState: Prepared drawing %d with %d steps for player %s", roundIdx+1, len(drawings), player.Name)
			}
		}
	}

	finalScoresPayload := messages.GameFinishedPayload{
		GamePhase:        p.Phase().String(),
		Players:          gs.getPlayerInfoList(),
		DrawingHistories: drawingHistories,
	}

	log.Printf("GameState: Broadcasting GameFinished message with %d players and %d drawing histories.", len(finalScoresPayload.Players), len(drawingHistories))
	go gs.Broadcaster.Broadcast(messages.GameFinishedResponse, finalScoresPayload)
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	log.Printf("GameState: Ignoring message type %s from player %s in GameOver phase.", msg.Type, player.Name)
	return p
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
