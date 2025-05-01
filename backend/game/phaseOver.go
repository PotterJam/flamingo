package game

import "backend/messages"

type GameOverHandler struct{}

func (p *GameOverHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *GameOverHandler) StartPhase(gs *GameState) {
	// todo
	return
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	// todo
	return p
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
