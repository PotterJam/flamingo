package phase

type RoundFinishedHandler struct{}

func (p *RoundFinishedHandler) Phase() GamePhase {
	return GamePhaseRoundFinished
}

func (p *RoundFinishedHandler) StartPhase(gs *GameState) {
	playerRoundScores := calculateRoundScores(gs)

	// Apply score deltas
	for _, player := range gs.Players {
		if delta, ok := playerRoundScores[player.Id]; ok {
			player.Score += delta
		}
	}

	finishDelay := 5 * time.Second
	gs.timerForTimeout = time.NewTimer(finishDelay)
	gs.turnEndTime = time.Now().Add(finishDelay)

	gs.BroadcastSystemMessage("Turn over! The word was: " + gs.Word)
	turnEndPayload := TurnEndPayload{
		CorrectWord: gs.Word,
		Players:     gs.getPlayerInfoList(),
		RoundScores: playerRoundScores,
	}
	turnEndMsg := Message{Type: TurnEndResponse, Payload: json.RawMessage(MustMarshal(turnEndPayload))}
	go gs.Room.Broadcast(turnEndMsg)
}

func (p *RoundFinishedHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	return p
}

func (p *RoundFinishedHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	log.Println("GameState: Delay finished, attempting to start next turn.")

	gs.CorrectGuessTimes = make(map[string]time.Time)
	gs.Word = ""

	if gs.IsActive {
		return GamePhaseHandler(&RoundSetupHandler{WordToPickFrom: nil})
	} else {
		log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		return GamePhaseHandler(&WaitingInLobbyHandler{})
	}
}
