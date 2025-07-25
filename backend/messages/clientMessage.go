package messages

const (
	ClientRegisterUser    = "setName"
	ClientGuess           = "guess"
	ClientChat            = "chat"
	ClientDrawEvent       = "drawEvent"
	ClientStartGame       = "startGame"
	ClientSelectRoundWord = "selectRoundWord"
	ClientPhaseChangeAck  = "phaseChangeAck"
	ClientDrawPathUndo    = "drawPathUndo"
)

type SetNamePayload struct {
	Name string `json:"name"`
}

type GuessPayload struct {
	Guess string `json:"guess"`
}

type ClientChatPayload struct {
	Message string `json:"message"`
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

type StartGamePayload struct {
	RoundCount  int `json:"roundCount"`
	RoundLength int `json:"roundLength"`
}
