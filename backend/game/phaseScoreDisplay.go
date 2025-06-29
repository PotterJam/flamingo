package game

import (
	"backend/messages"
	"log"
	"sort"
	"time"
)

type RoundScoreDisplayHandler struct{}

func (p *RoundScoreDisplayHandler) Phase() GamePhase {
	return GamePhaseRoundScoreDisplay
}

func (p *RoundScoreDisplayHandler) StartPhase(gs *GameState) {
	// Calculate round scores but don't apply them to player total scores yet
	playerRoundScores := calculateRoundScores(gs)

	// Create a sorted list of score gains for display
	scoreGains := make([]messages.PlayerScoreGain, 0, len(gs.Players))

	// Add all players with their score gains (including 0 gains)
	for _, player := range gs.Players {
		scoreGain := 0
		if gain, ok := playerRoundScores[player.Id]; ok {
			scoreGain = gain
		}
		scoreGains = append(scoreGains, messages.PlayerScoreGain{
			PlayerID:   player.Id,
			PlayerName: player.Name,
			ScoreGain:  scoreGain,
		})
	}

	// Sort by score gain (highest first), then by name for ties
	sort.Slice(scoreGains, func(i, j int) bool {
		if scoreGains[i].ScoreGain != scoreGains[j].ScoreGain {
			return scoreGains[i].ScoreGain > scoreGains[j].ScoreGain
		}
		return scoreGains[i].PlayerName < scoreGains[j].PlayerName
	})

	// Set up 5-second timer
	scoreDisplayDelay := 5 * time.Second
	gs.timerForTimeout = time.NewTimer(scoreDisplayDelay)
	gs.turnEndTime = time.Now().Add(scoreDisplayDelay)

	// Broadcast the score display message
	scoreDisplayPayload := messages.RoundScoreDisplayPayload{
		GamePhase:   p.Phase().String(),
		CorrectWord: gs.Word,
		ScoreGains:  scoreGains,
		Players:     gs.getPlayerInfoList(), // Current scores (before this round's gains)
	}

	log.Printf("GameState: Broadcasting round score display for 5 seconds")
	go gs.Broadcaster.Broadcast(messages.RoundScoreDisplayResponse, scoreDisplayPayload)
}

func (p *RoundScoreDisplayHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	// Ignore all messages during score display
	return p
}

func (p *RoundScoreDisplayHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	log.Println("GameState: Score display finished, transitioning to RoundFinished")
	return ackPhaseTransitionTo(&RoundFinishedHandler{})
}
