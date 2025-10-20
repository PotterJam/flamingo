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
	gs.turnEndTime = now.Add(gs.RoundDuration)
	gs.timerForTimeout = time.NewTimer(gs.RoundDuration)

	// Initialize drawing storage for this round
	gs.CurrentRoundDrawings = make([]interface{}, 0)

	gs.setupHintTimers()

	turnPayloadBase := messages.TurnStartPayload{
		GamePhase:       p.Phase().String(),
		CurrentDrawerID: gs.Players[gs.CurrentDrawerIdx].Id,
		WordOutline:     generateWordOutline(gs.Word),
		Players:         gs.getPlayerInfoList(),
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
		TotalRounds:     gs.TotalRounds,
		CurrentRound:    gs.CurrentRound,
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
		return p.handleChatMessage(gs, player, msg)
	}

	if msg.Type == messages.ClientGuess && !gs.isDrawer(player) {
		return p.handleGuessMessage(gs, player, msg)
	}

	if msg.Type == messages.ClientDrawEvent && gs.isDrawer(player) {
		return p.handleDrawEvent(gs, player, msg)
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

func (gs *GameState) allOtherPlayers(excludePlayer *Player) []*Player {
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for _, player := range gs.Players {
		if player != nil && player.Id != excludePlayer.Id {
			playersToSendTo = append(playersToSendTo, player)
		}
	}
	return playersToSendTo
}

func (p *RoundInProgressHandler) handleChatMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	var chatPayload messages.ClientChatPayload
	if err := json.Unmarshal(msg.Payload, &chatPayload); err != nil {
		player.SendError("Invalid chat format.")
		return p
	}
	gs.BroadcastChatMessage(player.Name, chatPayload.Message)
	return p
}

func (p *RoundInProgressHandler) handleGuessMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
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

	playersToNotify := gs.allOtherPlayers(player)
	go gs.Broadcaster.BroadcastToPlayers(messages.PlayerCorrectResponse, messages.PlayerCorrectPayload{
		PlayerID:   player.Id,
		PlayerName: player.Name,
	}, playersToNotify)

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

func (p *RoundInProgressHandler) handleDrawEvent(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	// Store the draw event for this player
	var drawEvent map[string]interface{}
	if err := json.Unmarshal(msg.Payload, &drawEvent); err == nil {
		gs.CurrentRoundDrawings = append(gs.CurrentRoundDrawings, drawEvent)
	}

	go gs.Broadcaster.BroadcastToPlayers(messages.DrawEventBroadcastResponse, msg.Payload, gs.allOtherPlayers(player))
	return p
}
