package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"strings"
	"time"
)

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

	gs.setupHintTimers()

	turnPayloadBase := messages.TurnStartPayload{
		GamePhase:       p.Phase().String(),
		CurrentDrawerID: gs.Players[gs.CurrentDrawerIdx].Id,
		WordOutline:     generateWordOutline(gs.Word),
		Players:         gs.getPlayerInfoList(),
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = gs.Word
	log.Printf("GameState: Sending TurnStart (with word) to drawer %s", drawer.Name)
	go drawer.SendMessage(messages.TurnStartResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go gs.Broadcaster.BroadcastToPlayers(messages.TurnStartResponse, guesserPayload, playersToSendTo)

	gs.BroadcastSystemMessage(drawer.Name + " is drawing!")
	return
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type == messages.ClientChat {
		var chatPayload messages.ClientChatPayload
		if err := json.Unmarshal(msg.Payload, &chatPayload); err != nil {
			player.SendError("Invalid chat format.")
			return p
		}
		gs.BroadcastChatMessage(player.Name, chatPayload.Message)
		return p
	}

	if msg.Type == messages.ClientGuess && !gs.isDrawer(player) {
		// If player has already guessed correctly they should be sending chat messages
		if _, alreadyGuessed := gs.CorrectGuessTimes[player.Id]; alreadyGuessed {
			return p
		}

		var guessPayload messages.GuessPayload
		if err := json.Unmarshal(msg.Payload, &guessPayload); err != nil {
			player.SendError("Invalid guess format.")
			return p
		}

		correct := strings.EqualFold(guessPayload.Guess, gs.Word)

		if !correct {
			gs.BroadcastChatMessage(player.Name, guessPayload.Guess)
			return p
		}

		gs.CorrectGuessTimes[player.Id] = time.Now()
		gs.BroadcastSystemMessage(player.Name + " guessed the word!")

		go player.SendMessage(messages.WordRevealResponse, messages.WordRevealPayload{
			Word: gs.Word,
		})

		gs.broadcastPlayerUpdate()

		if gs.checkAllGuessed() {
			return ackPhaseTransitionTo(&DelayHandler{
				NextPhase:     &RoundScoreDisplayHandler{},
				DelayDuration: 1 * time.Second,
				CurrentPhase:  GamePhaseRoundInProgress,
				DelayMessage:  "Starting 1-second delay before score display (all players guessed)",
			})
		}

		return p
	}

	if msg.Type == messages.ClientDrawEvent && gs.isDrawer(player) {
		playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
		for _, p := range gs.Players {
			if p != nil && p.Id != player.Id {
				playersToSendTo = append(playersToSendTo, p)
			}
		}

		go gs.Broadcaster.BroadcastToPlayers(messages.DrawEventBroadcastResponse, msg.Payload, playersToSendTo)
		return p
	}

	return p
}

func (p *RoundInProgressHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return ackPhaseTransitionTo(&DelayHandler{
		NextPhase:     &RoundScoreDisplayHandler{},
		DelayDuration: 1 * time.Second,
		CurrentPhase:  GamePhaseRoundInProgress,
		DelayMessage:  "Starting 1-second delay before score display (timer expired)",
	})
}
