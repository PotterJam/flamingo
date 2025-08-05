package game

import (
	"backend/messages"
	"backend/util"
	"hash/fnv"
	"log"
	"math/rand"
	"sync"
	"time"
)

type PlayerOperationType int

const (
	PlayerOpAdd PlayerOperationType = iota
	PlayerOpRemove
	// Add more operation types here as needed
	// PlayerOpKick
	// PlayerOpPromoteToHost
	// PlayerOpDemoteFromHost
)

type PlayerOperation struct {
	Type   PlayerOperationType
	Player *Player
	// Additional fields can be added here for more complex operations
	// Reason string // for kicks, bans, etc.
	// Data   interface{} // for custom operation data
}

type Broadcaster interface {
	Broadcast(msgType string, payload any)
	BroadcastToPlayers(msgType string, payload any, players []*Player)
}

// HintEvent represents a hint that should be sent
type HintEvent struct {
	HintLevel int    // 1 for 30s hint, 2 for 40s hint
	HintType  string // "30s", "40s"
}

type RasterCanvas = [][]Pixel

type CanvasState struct {
	PathStack *util.Stack[[]messages.DrawEventPayload]
	FillStack *util.Stack[RasterCanvas]
	Actions   *util.Stack[string]
}

// GameState represents the single, shared game session.
// TODO: move a bunch of this state into the phases.
type GameState struct {
	Players           []*Player
	HostId            string
	CurrentDrawerIdx  int                  // Index in Players slice of the current drawer (-1 if no game)
	Word              string               // The secret word for the current turn
	CorrectGuessTimes map[string]time.Time // player ID -> time they guessed correctly
	TurnStartTime     time.Time            // When the current turn (drawing phase) started
	Broadcaster       Broadcaster
	mu                sync.Mutex // Mutex to protect concurrent access to game state
	IsActive          bool       // Flag indicating if a round/turn is currently running

	RoundDuration time.Duration

	timerForTimeout *time.Timer
	turnEndTime     time.Time
	hintEvents      chan HintEvent // Channel for hint events

	TotalRounds                  int
	CurrentRound                 int
	PlayersWhoHaveDrawnThisRound []string

	// Channel for handlers to request player operations (add, remove, etc.)
	PlayerOperations chan PlayerOperation

	PrevX int
	PrevY int

	CanvasStack *util.Stack[*Canvas]
}

func (gs *GameState) broadcastPlayerUpdate() {
	payload := messages.PlayerUpdatePayload{
		Players: gs.getPlayerInfoList(), // Assumes lock held
		HostID:  gs.HostId,
	}

	go gs.Broadcaster.Broadcast(messages.PlayerUpdateResponse, payload)
}

func (gs *GameState) BroadcastSystemMessage(message string) {
	payload := messages.ChatPayload{SenderName: "System", Message: message, IsSystem: true}
	go gs.Broadcaster.Broadcast(messages.ChatResponse, payload)
}

func (gs *GameState) getPlayerInfoList() []messages.PlayerInfo {
	infoList := make([]messages.PlayerInfo, 0, len(gs.Players))
	for _, p := range gs.Players {
		if p != nil {
			_, hasGuessedCorrectly := gs.CorrectGuessTimes[p.Id]
			infoList = append(infoList, messages.PlayerInfo{
				ID:                  p.Id,
				Name:                p.Name,
				Score:               p.Score,
				IsHost:              p.Id == gs.HostId,
				HasGuessedCorrectly: hasGuessedCorrectly,
			})
		} else {
			log.Printf("GameState Error: Found nil player in g.Players during getPlayerInfoList")
		}
	}
	return infoList
}

func (gs *GameState) isDrawer(p *Player) bool {
	if !gs.IsActive {
		return false
	}

	if gs.CurrentDrawerIdx < 0 || gs.CurrentDrawerIdx >= len(gs.Players) {
		return false
	}

	return gs.Players[gs.CurrentDrawerIdx].Id == p.Id
}

func generateWordOutline(word string) []string {
	outline := make([]string, len(word))
	for i, char := range word {
		if (char >= 'A' && char <= 'Z') || (char >= 'a' && char <= 'z') {
			outline[i] = ""
		} else {
			outline[i] = string(char)
		}
	}
	return outline
}

// generateWordOutlineWithHints creates a word outline with some letters revealed based on hint level
// hintLevel: 0 = no hints, 1 = first hint (30s), 2 = second hint (40s)
// Letters are revealed randomly but deterministically based on the word
func generateWordOutlineWithHints(word string, hintLevel int) []string {
	outline := generateWordOutline(word)
	if hintLevel <= 0 {
		return outline
	}

	// Find all letter positions (excluding spaces, hyphens, etc.)
	letterPositions := make([]int, 0)
	for i, char := range word {
		if (char >= 'A' && char <= 'Z') || (char >= 'a' && char <= 'z') {
			letterPositions = append(letterPositions, i)
		}
	}

	if len(letterPositions) == 0 {
		return outline
	}

	// Use hash of the word as seed for consistent results
	hash := fnv.New32a()
	hash.Write([]byte(word))
	seed := int64(hash.Sum32())

	// Create a new random generator with the deterministic seed
	rng := rand.New(rand.NewSource(seed))

	// Don't reveal more letters than available (minus 1 to keep it challenging)
	maxRevealable := len(letterPositions) - 1
	if maxRevealable < 1 {
		maxRevealable = len(letterPositions)
	}

	lettersToReveal := hintLevel
	if lettersToReveal > maxRevealable {
		lettersToReveal = maxRevealable
	}

	// Generate only the positions we need for this hint level
	// Since we use the same seed, hint level N will always include
	// all positions from hint level N-1 plus additional ones
	usedPositions := make(map[int]bool)

	for i := 0; i < lettersToReveal; i++ {
		for {
			pos := letterPositions[rng.Intn(len(letterPositions))]
			if !usedPositions[pos] {
				usedPositions[pos] = true
				outline[pos] = string(word[pos])
				break
			}
		}
	}

	return outline
}

const (
	minPlayersToStart = 2
)

func (g *Game) sendGameInfo(player *Player) {
	state := g.GameState
	payload := messages.GameInfoPayload{
		GamePhase:    g.GameHandler.Phase().String(),
		YourID:       player.Id,
		Players:      state.getPlayerInfoList(),
		HostID:       state.HostId,
		IsGameActive: state.IsActive,
	}

	// Populate all available game state information
	if state.IsActive && state.CurrentDrawerIdx >= 0 && state.CurrentDrawerIdx < len(state.Players) {
		drawer := state.Players[state.CurrentDrawerIdx]
		payload.CurrentDrawerID = drawer.Id
		payload.WordOutline = generateWordOutline(state.Word)
		payload.TurnEndTime = state.turnEndTime.UnixMilli()
	}

	log.Printf("GameState: Sending game info to player %s (%s). Active: %t, Phase: %s", player.Id, player.Name, payload.IsGameActive, payload.GamePhase)
	go player.SendMessage(messages.GameInfoResponse, payload)
}

func (gs *GameState) HandleStartGame(sender *Player) {
	log.Printf("GameState: Received StartGame request from %s (%s)", sender.Id, sender.Name)

	if sender.Id != gs.HostId {
		log.Printf("GameState: StartGame denied. Player %s is not the host (%s).", sender.Name, gs.HostId)
		sender.SendError("Only the host can start the game.")
		return
	}
	if gs.IsActive {
		log.Println("GameState: StartGame denied. GameState is already active.")
		sender.SendError("The game is already in progress.")
		return
	}
	if len(gs.Players) < minPlayersToStart {
		log.Printf("GameState: StartGame denied. Not enough players (%d/%d).", len(gs.Players), minPlayersToStart)
		sender.SendError("Not enough players to start the game (minimum " + string(minPlayersToStart+'0') + ").")
		return
	}

	gs.CurrentRound = 0
	gs.PlayersWhoHaveDrawnThisRound = make([]string, 0)
}

func (gs *GameState) checkAllGuessed() bool {
	totalPlayers := len(gs.Players)

	if !gs.IsActive || totalPlayers < minPlayersToStart || gs.CurrentDrawerIdx < 0 || gs.CurrentDrawerIdx >= len(gs.Players) {
		return false
	}
	correctCount := 0
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			if _, guessed := gs.CorrectGuessTimes[p.Id]; guessed {
				correctCount++
			}
		}
	}

	requiredCorrect := totalPlayers - 1
	return correctCount == requiredCorrect
}

func (gs *GameState) BroadcastChatMessage(senderName, message string) {
	payload := messages.ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	go gs.Broadcaster.Broadcast(messages.ChatResponse, payload)
}

func (gs *GameState) setupHintTimers() {
	roundNum := gs.CurrentRound
	roundName := gs.CurrentDrawerIdx

	go func() {
		time.Sleep(29 * time.Second)
		if roundNum != gs.CurrentRound || roundName != gs.CurrentDrawerIdx {
			return
		}

		select {
		case gs.hintEvents <- HintEvent{HintLevel: 1, HintType: "30s"}:
		default:
			// Channel might be closed or full, ignore
		}
	}()

	go func() {
		time.Sleep(39 * time.Second)
		if roundNum != gs.CurrentRound || roundName != gs.CurrentDrawerIdx {
			return
		}

		select {
		case gs.hintEvents <- HintEvent{HintLevel: 2, HintType: "40s"}:
		default:
			// Channel might be closed or full, ignore
		}
	}()
}

func (gs *GameState) sendHintToGuessers(hintLevel int, hintType string) {
	if gs.Word == "" {
		return
	}

	hintOutline := generateWordOutlineWithHints(gs.Word, hintLevel)

	playersToSendTo := make([]*Player, 0)
	for i, player := range gs.Players {
		if i != gs.CurrentDrawerIdx { // Skip drawer
			if _, hasGuessed := gs.CorrectGuessTimes[player.Id]; !hasGuessed {
				playersToSendTo = append(playersToSendTo, player)
			}
		}
	}

	if len(playersToSendTo) == 0 {
		return
	}

	hintPayload := messages.TurnHelpPayload{
		WordOutline: hintOutline,
		HintType:    hintType,
	}

	log.Printf("GameState: Sending %s hint to %d players who haven't guessed", hintType, len(playersToSendTo))
	go gs.Broadcaster.BroadcastToPlayers(messages.TurnHelpResponse, hintPayload, playersToSendTo)
}
