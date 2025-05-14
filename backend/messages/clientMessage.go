package messages

const (
	ClientRegisterUser    = "setName"
	ClientGuess           = "guess"
	ClientDrawEvent       = "drawEvent"
	ClientStartGame       = "startGame"
	ClientSelectRoundWord = "selectRoundWord"
	ClientPhaseChangeAck  = "phaseChangeAck"
)

type SetNamePayload struct {
	Name string `json:"name"`
}

type GuessPayload struct {
	Guess string `json:"guess"`
}

type SelectRoundWordPayload struct {
	Word string `json:"word"`
}

type DrawEventPayload struct {
	EventType string  `json:"eventType"`
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Color     string  `json:"color,omitempty"`
	LineWidth float64 `json:"lineWidth,omitempty"`
}

type ClientPhaseChangeAckPayload struct {
	NewPhase string `json:"newPhase"`
}

// StartGamePayload: No payload needed
