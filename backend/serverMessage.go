package main // Ensure this is package main

const (
	TypeErrorResponse              = "error"
	GameInfoResponse               = "gameInfo"
	PlayerUpdateResponse           = "playerUpdate"
	TurnStartResponse              = "turnStart"
	PlayerGuessedCorrectlyResponse = "playerGuessedCorrectly"
	ChatResponse                   = "chat"
	DrawEventBroadcastResponse     = "drawEvent" // <<< Using "drawEvent" to match frontend expectation
	TurnEndResponse                = "turnEnd"
)

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
