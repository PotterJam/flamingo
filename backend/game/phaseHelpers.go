package game

func ackPhaseTransitionTo(handler GamePhaseHandler) GamePhaseHandler {
	return GamePhaseHandler(&PhaseChangeHandler{
		HandlerToChangeTo: handler,
		AckedPlayers:      make([]string, 0),
	})
}
