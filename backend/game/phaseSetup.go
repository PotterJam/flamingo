package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"math/rand"
	"time"
)

// RoundSetupHandler Useless for now until adding word selection etc
type RoundSetupHandler struct {
	WordToPickFrom *[]string
}

func (p *RoundSetupHandler) Phase() GamePhase {
	return GamePhaseRoundSetup
}

func (p *RoundSetupHandler) StartPhase(gs *GameState) {
	gs.turnEndTime = time.Now().Add(10 * time.Second)
	gs.timerForTimeout = time.NewTimer(10 * time.Second)

	gs.CurrentDrawerIdx = (gs.CurrentDrawerIdx + 1) % len(gs.Players)
	newDrawer := gs.Players[gs.CurrentDrawerIdx]

	wordChoices := make([]string, 3)
	perms := rand.Perm(len(words))
	for i, r := range perms[:len(wordChoices)] {
		wordChoices[i] = words[r]
	}
	p.WordToPickFrom = &wordChoices

	turnPayloadBase := messages.TurnSetupPayload{
		CurrentDrawerID: newDrawer.Id,
		Players:         gs.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.WordChoices = *p.WordToPickFrom
	log.Printf("GameState: Sending TurnSetup (with word choices) to drawer %s", newDrawer.Name)
	go newDrawer.SendMessage(messages.TurnSetupResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	msg := messages.Message{Type: messages.TurnSetupResponse, Payload: json.RawMessage(messages.MustMarshal(guesserPayload))}
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnSetup (no word choices) to %d guessers", len(playersToSendTo))
	go gs.Broadcaster.BroadcastToPlayers(msg, playersToSendTo)

	gs.BroadcastSystemMessage(newDrawer.Name + " is choosing a word.")
	return
}

func (p *RoundSetupHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type != messages.ClientSelectRoundWord || !gs.isDrawer(player) {
		return p
	}

	if len(gs.Players) < minPlayersToStart {
		log.Println("GameState: Cannot start next turn, less than minimum players.")
		return ackPhaseTransitionTo(&GameOverHandler{})
	}

	var roundWordPayload messages.SelectRoundWordPayload
	if err := json.Unmarshal(msg.Payload, &roundWordPayload); err != nil {
		player.SendError("Invalid guess format.")
		return p
	}

	// TODO: check that player hasn't picked a random word, make sure it's in the list of p.WordToPickFrom
	return ackPhaseTransitionTo(&RoundInProgressHandler{Word: roundWordPayload.Word})
}

func (p *RoundSetupHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	word := (*p.WordToPickFrom)[rand.Intn(len(*p.WordToPickFrom))]
	return ackPhaseTransitionTo(&RoundInProgressHandler{Word: word})
}
