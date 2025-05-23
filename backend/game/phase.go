package game

import "backend/messages"

type GamePhase int

const (
	GamePhaseWaitingInLobby GamePhase = iota
	GamePhaseRoundSetup
	GamePhaseRoundInProgress
	GamePhaseRoundFinished
	GamePhaseGameOver
	GamePhaseError
	GamePhaseChangeAck
)

var stateName = map[GamePhase]string{
	GamePhaseWaitingInLobby:  "WaitingInLobby",
	GamePhaseRoundSetup:      "RoundSetup",
	GamePhaseRoundInProgress: "RoundInProgress",
	GamePhaseRoundFinished:   "RoundFinished",
	GamePhaseGameOver:        "GameOver",
	GamePhaseError:           "Error",
	GamePhaseChangeAck:       "PhaseChangeAck",
}

func (ss GamePhase) String() string {
	return stateName[ss]
}

type GamePhaseHandler interface {
	Phase() GamePhase
	StartPhase(gs *GameState)
	HandleMessage(gs *GameState, playerID *Player, msg messages.Message) GamePhaseHandler
	HandleTimeOut(gs *GameState) GamePhaseHandler // Some phases have timeouts, this is good enough for now but can be improved
}
