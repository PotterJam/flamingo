package main // Ensure this is package main

import (
	"encoding/json"
)

// --- Message Constants ---
const (
	// Client -> Server
	MsgTypeRegisterUser = "setName"
	MsgTypeGuess        = "guess"
	MsgTypeDrawEvent    = "drawEvent"
	MsgTypeStartGame    = "startGame"
	// Server -> Client
	MsgTypeError                  = "error"
	MsgTypeGameInfo               = "gameInfo"
	MsgTypePlayerUpdate           = "playerUpdate"
	MsgTypeTurnStart              = "turnStart"
	MsgTypePlayerGuessedCorrectly = "playerGuessedCorrectly"
	MsgTypeChat                   = "chat"
	MsgTypeDrawEventBroadcast     = "drawEvent" // <<< Use "drawEvent" to match frontend expectation
	MsgTypeTurnEnd                = "turnEnd"
	MsgTypeWaiting                = "waiting" // Added back for potential use
)

// --- Message Structs ---

// Generic message structure
type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// --- Client -> Server Payloads ---

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

// --- Server -> Client Payloads ---

type ErrorPayload struct {
	Message string `json:"message"`
}

type PlayerInfo struct {
	ID                  string `json:"id"`
	Name                string `json:"name"`
	IsHost              bool   `json:"isHost,omitempty"`
	HasGuessedCorrectly bool   `json:"hasGuessedCorrectly,omitempty"`
}

type GameInfoPayload struct {
	YourID          string       `json:"yourId"`
	Players         []PlayerInfo `json:"players"`
	HostID          string       `json:"hostId,omitempty"`
	IsGameActive    bool         `json:"isGameActive"`
	CurrentDrawerID string       `json:"currentDrawerId,omitempty"`
	WordLength      int          `json:"wordLength,omitempty"`
	Word            string       `json:"word,omitempty"` // For drawer on join/rejoin
	TurnEndTime     int64        `json:"turnEndTime,omitempty"`
}

type PlayerUpdatePayload struct {
	Players []PlayerInfo `json:"players"`
	HostID  string       `json:"hostId,omitempty"`
}

type TurnStartPayload struct {
	CurrentDrawerID string       `json:"currentDrawerId"`
	Word            string       `json:"word,omitempty"`
	WordLength      int          `json:"wordLength"`
	Players         []PlayerInfo `json:"players"`
	TurnEndTime     int64        `json:"turnEndTime"`
}

type PlayerGuessedCorrectlyPayload struct {
	PlayerID string `json:"playerId"`
}

type ChatPayload struct {
	SenderName string `json:"senderName"`
	Message    string `json:"message"`
	IsSystem   bool   `json:"isSystem,omitempty"`
}

type TurnEndPayload struct {
	CorrectWord string `json:"correctWord"`
}

// WaitingPayload: No payload needed for MsgTypeWaiting
