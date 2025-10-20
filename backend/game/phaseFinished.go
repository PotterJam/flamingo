package game

import (
	"backend/messages"
	"log"
	"time"
)

type RoundFinishedHandler struct{}

func (p *RoundFinishedHandler) Phase() GamePhase {
	return GamePhaseRoundFinished
}

func (p *RoundFinishedHandler) StartPhase(gs *GameState) {
	// Calculate and apply round scores to players
	playerRoundScores := calculateRoundScores(gs)

	for _, player := range gs.Players {
		if roundScore, ok := playerRoundScores[player.Id]; ok {
			player.Score += roundScore
		}
	}

	// Save the drawing history for the current drawer
	if gs.CurrentDrawerIdx >= 0 && gs.CurrentDrawerIdx < len(gs.Players) {
		drawer := gs.Players[gs.CurrentDrawerIdx]
		// Append this round's drawings as a new entry
		if _, exists := gs.PlayerDrawingHistories[drawer.Id]; !exists {
			gs.PlayerDrawingHistories[drawer.Id] = make([][]interface{}, 0)
		}
		gs.PlayerDrawingHistories[drawer.Id] = append(gs.PlayerDrawingHistories[drawer.Id], gs.CurrentRoundDrawings)
		log.Printf("GameState: Saved %d draw events for player %s (total rounds drawn: %d)", len(gs.CurrentRoundDrawings), drawer.Name, len(gs.PlayerDrawingHistories[drawer.Id]))
	}

	gs.PlayersWhoHaveDrawnThisRound = append(gs.PlayersWhoHaveDrawnThisRound, gs.Players[gs.CurrentDrawerIdx].Id)

	// Use very short timeout to immediately proceed to next phase
	gs.timerForTimeout = time.NewTimer(1 * time.Millisecond)
	gs.turnEndTime = time.Now().Add(1 * time.Millisecond)

	// Send turn end message with updated scores
	turnEndPayload := messages.TurnEndPayload{
		GamePhase:   p.Phase().String(),
		CorrectWord: gs.Word,
		Players:     gs.getPlayerInfoList(), // Now includes updated scores
		RoundScores: playerRoundScores,
	}

	go gs.Broadcaster.Broadcast(messages.TurnEndResponse, turnEndPayload)
}

func (p *RoundFinishedHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	return p
}

func (p *RoundFinishedHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	log.Println("GameState: Delay finished, attempting to start next turn.")

	gs.CorrectGuessTimes = make(map[string]time.Time)
	gs.Word = ""

	// Check if game should end due to rounds
	numPlayers := len(gs.Players)
	if numPlayers > 0 && len(gs.PlayersWhoHaveDrawnThisRound) >= numPlayers {
		gs.CurrentRound++
		gs.PlayersWhoHaveDrawnThisRound = make([]string, 0)
		log.Printf("GameState: Round %d completed.", gs.CurrentRound)
	}

	if gs.CurrentRound >= gs.TotalRounds {
		log.Printf("GameState: Final round (%d/%d) finished. Game Over.", gs.CurrentRound, gs.TotalRounds)
		return ackPhaseTransitionTo(&GameOverHandler{})
	}

	if gs.IsActive {
		return ackPhaseTransitionTo(&RoundSetupHandler{WordToPickFrom: nil})
	} else {
		log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		return ackPhaseTransitionTo(&WaitingInLobbyHandler{})
	}
}
