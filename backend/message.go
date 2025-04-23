package main

import "encoding/json"

var words = []string{"apple", "banana", "cloud", "house", "tree", "computer", "go", "svelte"}

// --- Message Constants ---
const (
	MsgTypeError        = "error"
	MsgTypeAssignRole   = "assignRole"
	MsgTypeGameState    = "gameState"
	MsgTypeDrawEvent    = "drawEvent"
	MsgTypeGuess        = "guess"
	MsgTypeGuessResult  = "guessResult"
	MsgTypePlayerJoined = "playerJoined" // Example, not fully used in this basic version
	MsgTypePlayerLeft   = "playerLeft"
	MsgTypeWaiting      = "waiting"
	MsgTypeGameStart    = "gameStart"
	MsgTypeGameOver     = "gameOver"
	MsgTypeClearCanvas  = "clearCanvas" // Todo: Add a clear button
)

// --- Message Structs ---

// Generic message structure to determine type before full unmarshalling
type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"` // Use RawMessage to delay parsing payload
}

// Specific payload structures for different message types

type AssignRolePayload struct {
	Role       string `json:"role"`                 // "drawer" or "guesser"
	Word       string `json:"word,omitempty"`       // Only sent to drawer
	WordLength int    `json:"wordLength,omitempty"` // Only sent to guesser
}

type DrawEventPayload struct {
	// Define fields needed for drawing (match frontend)
	EventType string  `json:"eventType"` // e.g., "start", "draw", "end"
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Color     string  `json:"color,omitempty"`     // Optional: Add color selection
	LineWidth float64 `json:"lineWidth,omitempty"` // Optional: Add line width
}

type GuessPayload struct {
	Guess string `json:"guess"`
}

type GuessResultPayload struct {
	Correct bool   `json:"correct"`
	Guess   string `json:"guess,omitempty"` // Optionally include the guess text for feedback
	Word    string `json:"word,omitempty"`  // Send the correct word on game over
}

type GameStatePayload struct {
	State string `json:"state"` // e.g., "waiting", "active", "gameOver"
}

type ErrorPayload struct {
	Message string `json:"message"`
}

// Payload for player leaving (sent to remaining player)
type PlayerLeftPayload struct {
	PlayerID string `json:"playerId"`
}
