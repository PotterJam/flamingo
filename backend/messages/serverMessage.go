package messages

const (
	TypeErrorResponse          = "error"
	GameInfoResponse           = "gameInfo"
	PlayerUpdateResponse       = "playerUpdate"
	TurnStartResponse          = "turnStart"
	ChatResponse               = "chat"
	DrawEventBroadcastResponse = "drawEvent" // <<< Using "drawEvent" to match frontend expectation
	TurnSetupResponse          = "turnSetup"
	TurnEndResponse            = "turnEnd"
	GameFinishedResponse       = "gameFinished"
	PhaseChangeAckResponse     = "phaseChangeAckResponse"
)

type ErrorPayload struct {
	Message string `json:"message"`
}

type PlayerInfo struct {
	ID                  string `json:"id"`
	Name                string `json:"name"`
	Score               int    `json:"score"`
	IsHost              bool   `json:"isHost,omitempty"`
	HasGuessedCorrectly bool   `json:"hasGuessedCorrectly,omitempty"`
}

type GameInfoPayload struct {
	GamePhase       string       `json:"gamePhase"`
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

type TurnSetupPayload struct {
	CurrentDrawerID string       `json:"currentDrawerId"`
	WordChoices     []string     `json:"wordChoices,omitempty"`
	Players         []PlayerInfo `json:"players"`
	TurnEndTime     int64        `json:"turnEndTime"`
}

type TurnStartPayload struct {
	CurrentDrawerID string `json:"currentDrawerId"`
	Word            string `json:"word,omitempty"`
	WordLength      int    `json:"wordLength"`
	// TODO: word constants like hyphens and spaces in an array of tuples with their location
	Players     []PlayerInfo `json:"players"`
	TurnEndTime int64        `json:"turnEndTime"`
}

type PhaseChangeAckPayload struct {
	NewPhase string `json:"newPhase"`
}

// TODO: TurnHelpPayload that gives help for people that haven#t guessed the word

type ChatPayload struct {
	SenderName string `json:"senderName"`
	Message    string `json:"message"`
	IsSystem   bool   `json:"isSystem,omitempty"`
}

type TurnEndPayload struct {
	CorrectWord string         `json:"correctWord"`
	Players     []PlayerInfo   `json:"players"`
	RoundScores map[string]int `json:"roundScores"`
}

type GameFinishedPayload struct {
	Players []PlayerInfo `json:"players"`
}
