package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"sync"
	"time"
)

type Broadcaster interface {
	Broadcast(m messages.Message)
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

	timerForTimeout *time.Timer
	turnEndTime     time.Time
}

func (g *GameState) broadcastPlayerUpdate() {
	payload := messages.PlayerUpdatePayload{
		Players: g.getPlayerInfoList(), // Assumes lock held
		HostID:  g.HostId,
	}
	msg := messages.Message{Type: messages.PlayerUpdateResponse, Payload: json.RawMessage(messages.MustMarshal(payload))}
	go g.Broadcaster.Broadcast(msg)
}

func (g *GameState) BroadcastSystemMessage(message string) {
	payload := messages.ChatPayload{SenderName: "System", Message: message, IsSystem: true}
	msg := messages.Message{Type: messages.ChatResponse, Payload: json.RawMessage(messages.MustMarshal(payload))}
	go g.Broadcaster.Broadcast(msg)
}

func (g *GameState) getPlayerInfoList() []messages.PlayerInfo {
	infoList := make([]messages.PlayerInfo, 0, len(g.Players))
	for _, p := range g.Players {
		if p != nil {
			_, hasGuessedCorrectly := g.CorrectGuessTimes[p.Id]
			infoList = append(infoList, messages.PlayerInfo{
				ID:                  p.Id,
				Name:                p.Name,
				Score:               p.Score,
				IsHost:              p.Id == g.HostId,
				HasGuessedCorrectly: hasGuessedCorrectly,
			})
		} else {
			log.Printf("GameState Error: Found nil player in g.Players during getPlayerInfoList")
		}
	}
	return infoList
}

func (g *GameState) isDrawer(p *Player) bool {
	if !g.IsActive {
		return false
	}

	if g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}

	return g.Players[g.CurrentDrawerIdx].Id == p.Id
}

var words = []string{"apple", "banana", "cloud", "house", "tree", "computer", "go", "svelte", "network", "game", "player", "draw", "timer", "guess", "score", "host", "lobby", "react"}

var turnDuration = 59 * time.Second

const (
	minPlayersToStart = 2
)

// sendGameInfo sends the initial game state to a player
func (g *Game) sendGameInfo(player *Player) {
	state := g.GameState
	payload := messages.GameInfoPayload{
		GamePhase:    g.GameHandler.Phase().String(),
		YourID:       player.Id,
		Players:      state.getPlayerInfoList(),
		HostID:       state.HostId,
		IsGameActive: state.IsActive,
	}

	if state.IsActive && state.CurrentDrawerIdx >= 0 && state.CurrentDrawerIdx < len(state.Players) {
		payload.CurrentDrawerID = state.Players[state.CurrentDrawerIdx].Id
		payload.WordLength = len(state.Word)
		payload.TurnEndTime = state.turnEndTime.UnixMilli()
		if player.Id == payload.CurrentDrawerID {
			payload.Word = state.Word
		}
	}
	log.Printf("GameState: Sending game info to player %s (%s). Active: %t, Host: %s", player.Id, player.Name, payload.IsGameActive, state.HostId)
	go player.SendMessage(messages.GameInfoResponse, payload)
}

func (g *GameState) HandleStartGame(sender *Player) {
	log.Printf("GameState: Received StartGame request from %s (%s)", sender.Id, sender.Name)

	if sender.Id != g.HostId {
		log.Printf("GameState: StartGame denied. Player %s is not the host (%s).", sender.Name, g.HostId)
		sender.SendError("Only the host can start the game.")
		return
	}
	if g.IsActive {
		log.Println("GameState: StartGame denied. GameState is already active.")
		sender.SendError("The game is already in progress.")
		return
	}
	if len(g.Players) < minPlayersToStart {
		log.Printf("GameState: StartGame denied. Not enough players (%d/%d).", len(g.Players), minPlayersToStart)
		sender.SendError("Not enough players to start the game (minimum " + string(minPlayersToStart+'0') + ").")
		return
	}
}

func (g *GameState) checkAllGuessed() bool {
	totalPlayers := len(g.Players)

	if !g.IsActive || totalPlayers < minPlayersToStart || g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}
	correctCount := 0
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx {
			if _, guessed := g.CorrectGuessTimes[p.Id]; guessed {
				correctCount++
			}
		}
	}

	requiredCorrect := totalPlayers - 1
	return correctCount == requiredCorrect
}

func (g *GameState) BroadcastChatMessage(senderName, message string) {
	payload := messages.ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	msg := messages.Message{Type: messages.ChatResponse, Payload: json.RawMessage(messages.MustMarshal(payload))}
	go g.Broadcaster.Broadcast(msg)
}
