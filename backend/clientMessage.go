package main

const (
	ClientRegisterUser = "setName"
	ClientGuess        = "guess"
	ClientDrawEvent    = "drawEvent"
	ClientStartGame    = "startGame"
	ClientSelectedWord = "selectedWord"
)

type SetNamePayload struct {
	Name string `json:"name"`
}

type GuessPayload struct {
	Guess string `json:"guess"`
}

type DrawEventPayload struct {
	EventType string  `json:"eventType"`
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Color     string  `json:"color,omitempty"`
	LineWidth float64 `json:"lineWidth,omitempty"`
}

// StartGamePayload: No payload needed
