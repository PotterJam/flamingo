package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"time"
)

type RoundFinishedHandler struct{}

func (p *RoundFinishedHandler) Phase() GamePhase {
	return GamePhaseRoundFinished
}

func (p *RoundFinishedHandler) StartPhase(gs *GameState) {
	playerRoundScores := calculateRoundScores(gs)

	for _, player := range gs.Players {
		if roundScore, ok := playerRoundScores[player.Id]; ok {
			player.Score += roundScore
		}
	}

	gs.PlayersWhoHaveDrawnThisRound = append(gs.PlayersWhoHaveDrawnThisRound, gs.Players[gs.CurrentDrawerIdx].Id)

	finishDelay := 5 * time.Second
	gs.timerForTimeout = time.NewTimer(finishDelay)
	gs.turnEndTime = time.Now().Add(finishDelay)

	gs.BroadcastSystemMessage("Turn over! The word was: " + gs.Word)
	turnEndPayload := messages.TurnEndPayload{
		CorrectWord: gs.Word,
		Players:     gs.getPlayerInfoList(),
		RoundScores: playerRoundScores,
	}
	turnEndMsg := messages.Message{Type: messages.TurnEndResponse, Payload: json.RawMessage(messages.MustMarshal(turnEndPayload))}
	go gs.Broadcaster.Broadcast(turnEndMsg)
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
		return GamePhaseHandler(&GameOverHandler{})
	}

	if gs.IsActive {
		return GamePhaseHandler(&RoundSetupHandler{WordToPickFrom: nil})
	} else {
		log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		return GamePhaseHandler(&WaitingInLobbyHandler{})
	}
}
