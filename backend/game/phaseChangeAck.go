package game

import "backend/messages"

type PhaseChangeHandler struct {
	HandlerToChangeTo GamePhaseHandler
	AckedPlayers      []string
}

func (p *PhaseChangeHandler) Phase() GamePhase {
	return GamePhaseChangeAck
}

func (p *PhaseChangeHandler) StartPhase(gs *GameState) {
	// todo
	return
}

func (p *PhaseChangeHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	// Once everyone has acked
	return p.HandlerToChangeTo
}

func (p *PhaseChangeHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
