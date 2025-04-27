package main

type PhaseType int

const (
	PhaseWaitingInLobby PhaseType = iota
	PhaseRoundSetup
	PhaseRoundInProgress
	PhaseGameOver
	PhaseError
)

var stateName = map[PhaseType]string{
	PhaseWaitingInLobby:  "WaitingInLobby",
	PhaseRoundSetup:      "RoundSetup",
	PhaseRoundInProgress: "RoundInProgress",
	PhaseGameOver:        "GameOver",
	PhaseError:           "Error",
}

func (ss PhaseType) String() string {
	return stateName[ss]
}

type PhaseHandler interface {
	HandleMessage(gs *Game, playerID string, msg Message) error
	Enter(gs *Game)
	Exit(gs *Game)
}
