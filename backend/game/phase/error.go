package phase

type ErrorHandler struct{}

func (p *ErrorHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *ErrorHandler) StartPhase(gs *GameState) {
	// todo
	return
}

func (p *ErrorHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return p
}

func (p *ErrorHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}
