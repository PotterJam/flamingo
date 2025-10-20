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
	RoundScoreDisplayResponse  = "roundScoreDisplay"
	GameFinishedResponse       = "gameFinished"
	PhaseChangeAckResponse     = "phaseChangeAck"
	WordRevealResponse         = "wordReveal"
	TurnHelpResponse           = "turnHelp"
	PlayerCorrectResponse      = "playerCorrect"
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
	WordOutline     []string     `json:"wordOutline,omitempty"`
	Word            string       `json:"word,omitempty"` // For drawer
	TurnEndTime     int64        `json:"turnEndTime,omitempty"`
}

type PlayerUpdatePayload struct {
	Players []PlayerInfo `json:"players"`
	HostID  string       `json:"hostId,omitempty"`
}

type TurnSetupPayload struct {
	GamePhase       string       `json:"gamePhase"`
	CurrentDrawerID string       `json:"currentDrawerId"`
	WordChoices     []string     `json:"wordChoices,omitempty"`
	Players         []PlayerInfo `json:"players"`
	TurnEndTime     int64        `json:"turnEndTime"`
}

type TurnStartPayload struct {
	GamePhase       string   `json:"gamePhase"`
	CurrentDrawerID string   `json:"currentDrawerId"`
	Word            string   `json:"word,omitempty"`
	WordOutline     []string `json:"wordOutline"`
	// TODO: word constants like hyphens and spaces in an array of tuples with their location
	Players      []PlayerInfo `json:"players"`
	TurnEndTime  int64        `json:"turnEndTime"`
	TotalRounds  int          `json:"totalRounds"`
	CurrentRound int          `json:"currentRound"`
}

type PhaseChangeAckPayload struct {
	NewPhase string `json:"newPhase"`
}

type TurnHelpPayload struct {
	WordOutline []string `json:"wordOutline"`
	HintType    string   `json:"hintType"` // "30s", "40s", etc.
}

type ChatPayload struct {
	SenderName string `json:"senderName"`
	Message    string `json:"message"`
	IsSystem   bool   `json:"isSystem,omitempty"`
}

type TurnEndPayload struct {
	GamePhase   string         `json:"gamePhase"`
	CorrectWord string         `json:"correctWord"`
	Players     []PlayerInfo   `json:"players"`
	RoundScores map[string]int `json:"roundScores"`
}

type PlayerScoreGain struct {
	PlayerID   string `json:"playerId"`
	PlayerName string `json:"playerName"`
	ScoreGain  int    `json:"scoreGain"`
}

type PlayerCorrectPayload struct {
	PlayerID   string `json:"playerId"`
	PlayerName string `json:"playerName"`
}

type RoundScoreDisplayPayload struct {
	GamePhase   string            `json:"gamePhase"`
	CorrectWord string            `json:"correctWord"`
	ScoreGains  []PlayerScoreGain `json:"scoreGains"`
	Players     []PlayerInfo      `json:"players"`
}

type PlayerDrawingHistory struct {
	PlayerID     string        `json:"playerId"`
	PlayerName   string        `json:"playerName"`
	DrawingSteps []interface{} `json:"drawingSteps"`
}

type GameFinishedPayload struct {
	GamePhase        string                 `json:"gamePhase"`
	Players          []PlayerInfo           `json:"players"`
	DrawingHistories []PlayerDrawingHistory `json:"drawingHistories"`
}

type WordRevealPayload struct {
	Word string `json:"word"`
}
