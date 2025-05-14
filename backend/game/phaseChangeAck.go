package game

import (
	"backend/messages"
	"encoding/json"
	"slices"
)

type PhaseChangeHandler struct {
	HandlerToChangeTo GamePhaseHandler
	AckedPlayers      []string
}

func (p *PhaseChangeHandler) Phase() GamePhase {
	return GamePhaseChangeAck
}

func (p *PhaseChangeHandler) StartPhase(gs *GameState) {
	ackPayload := messages.PhaseChangeAckPayload{
		NewPhase: p.HandlerToChangeTo.Phase().String(),
	}

	turnEndMsg := messages.Message{Type: messages.PhaseChangeAckResponse, Payload: json.RawMessage(messages.MustMarshal(ackPayload))}
	go gs.Broadcaster.Broadcast(turnEndMsg)

	return
}

func (p *PhaseChangeHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type == messages.ClientPhaseChangeAck && !slices.Contains(p.AckedPlayers, player.Id) {
		var payload messages.ClientPhaseChangeAckPayload
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			player.SendError("Invalid phase change ack payload.")
		} else if payload.NewPhase != p.HandlerToChangeTo.Phase().String() {
			player.SendError("Sent the wrong phase in ack payload.")
		} else {
			p.AckedPlayers = append(p.AckedPlayers, player.Id)
		}
	}

	// TODO (JP): a bit brittle with disconnecting/reconnecting, use equivalence or use a _not acked_ list instead
	if len(gs.Players) != len(p.AckedPlayers) {
		return p
	}

	return p.HandlerToChangeTo
}

func (p *PhaseChangeHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	// TODO (JP): if all players don't ack within a limit, remove them from the game and continue
	return p
}
