package game

func ackPhaseTransitionTo(handler GamePhaseHandler) GamePhaseHandler {
	return ackPhaseTransitionTo(&PhaseChangeHandler{
		HandlerToChangeTo: handler,
		AckedPlayers:      make([]string, 0),
	})
}
