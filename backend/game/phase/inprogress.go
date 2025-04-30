package phase

import "time"

type RoundInProgressHandler struct {
	Word string
}

func (p *RoundInProgressHandler) Phase() GamePhase {
	return GamePhaseRoundInProgress
}

func (p *RoundInProgressHandler) StartPhase(gs *GameState) {
	gs.CorrectGuessTimes = make(map[string]time.Time)

	if gs.CurrentDrawerIdx < -1 || gs.CurrentDrawerIdx >= len(gs.Players) {
		log.Printf("GameState: Resetting invalid CurrentDrawerIdx (%d) before next turn.", gs.CurrentDrawerIdx)
		gs.CurrentDrawerIdx = -1
	}

	drawer := gs.Players[gs.CurrentDrawerIdx]

	gs.Word = p.Word
	now := time.Now()
	gs.TurnStartTime = now
	gs.turnEndTime = now.Add(turnDuration)
	gs.timerForTimeout = time.NewTimer(turnDuration)

	turnPayloadBase := TurnStartPayload{
		CurrentDrawerID: drawer.Id,
		WordLength:      len(gs.Word),
		Players:         gs.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = gs.Word
	log.Printf("GameState: Sending TurnStart (with word) to drawer %s", drawer.Name)
	go drawer.SendMessage(TurnStartResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	msg := Message{Type: TurnStartResponse, Payload: json.RawMessage(MustMarshal(guesserPayload))}
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go gs.Room.BroadcastToPlayers(msg, playersToSendTo)

	gs.BroadcastSystemMessage(drawer.Name + " is drawing!")
	return
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type == ClientGuess && !gs.isDrawer(player) {
		if _, alreadyGuessed := gs.CorrectGuessTimes[player.Id]; alreadyGuessed {
			return p
		}

		var guessPayload GuessPayload
		if err := json.Unmarshal(msg.Payload, &guessPayload); err != nil {
			player.SendError("Invalid guess format.")
			return p
		}

		correct := guessPayload.Guess == gs.Word

		if correct {
			gs.CorrectGuessTimes[player.Id] = time.Now()
			gs.BroadcastSystemMessage(player.Name + " guessed the word!")

			if gs.checkAllGuessed() {
				return GamePhaseHandler(&RoundFinishedHandler{})
			}
		} else {
			gs.BroadcastChatMessage(player.Name, guessPayload.Guess)
		}
	} else if msg.Type == ClientDrawEvent && gs.isDrawer(player) {
		drawMsg := Message{Type: DrawEventBroadcastResponse, Payload: msg.Payload}
		playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
		for _, p := range gs.Players {
			if p != nil && p.Id != player.Id {
				playersToSendTo = append(playersToSendTo, p)
			}
		}

		go gs.Room.BroadcastToPlayers(drawMsg, playersToSendTo)
	}
	return p
}

func (p *RoundInProgressHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
