package main

import (
	"log"
	"slices"
	"time"
)

type Game struct {
	GameHandler GamePhaseHandler
	GameState   *GameState
}

func (g *Game) HandleMessage(playerID *Player, msg Message) {
	g.GameState.mu.Lock()
	defer g.GameState.mu.Unlock()

	var newHandler GamePhaseHandler
	if g.GameState.turnTimer != nil && time.Now().After(g.GameState.turnEndTime) {
		newHandler = g.GameHandler.HandleTimeOut(g.GameState)
	} else {
		newHandler = g.GameHandler.HandleMessage(g.GameState, playerID, msg)
	}

	if newHandler.Phase() != g.GameHandler.Phase() {
		newHandler.StartPhase(g.GameState)
		g.GameHandler = newHandler
	}
}

func NewGame(room *Room) *Game {
	initialHandler := WaitingInLobbyHandler{}
	handler := GamePhaseHandler(&initialHandler)

	return &Game{
		GameState: &GameState{
			Players:          make([]*Player, 0, 10),
			HostId:           "", // No host initially
			CurrentDrawerIdx: -1,
			GuessedCorrectly: make(map[string]bool),
			Room:             room,
			IsActive:         false,
		},
		GameHandler: handler,
	}
}

// resetGameState resets the game state (e.g., not enough players)
func (g *GameState) resetGameState(reason string) {
	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}
	g.IsActive = false
	g.CurrentDrawerIdx = -1
	g.Word = ""
	g.GuessedCorrectly = make(map[string]bool)
	g.turnEndTime = time.Time{}
	g.BroadcastSystemMessage("GameState Over: " + reason)
}

func (g *Game) AddPlayer(player *Player) {
	state := g.GameState

	state.mu.Lock()
	defer state.mu.Unlock()

	// Avoid adding duplicates
	for _, p := range state.Players {
		if p.Id == player.Id {
			log.Printf("GameState: Player %s (%s) already marked as ready.", player.Id, player.Name)
			state.sendGameInfo(player)
			return
		}
	}

	state.Players = append(state.Players, player)
	log.Printf("GameState: Player %s (%s) marked ready. Total ready players: %d", player.Id, player.Name, len(state.Players))

	// Assign host to the first player
	if len(state.Players) == 1 {
		state.HostId = player.Id
		log.Printf("GameState: Player %s (%s) assigned as Host.", player.Id, player.Name)
	}

	state.sendGameInfo(player)
	state.broadcastPlayerUpdate()
}

func (g *Game) RemovePlayer(player *Player) {
	state := g.GameState
	state.mu.Lock()
	defer state.mu.Unlock()

	found := false
	playerIndex := -1
	for i, p := range state.Players {
		if p != nil && p.Id == player.Id {
			found = true
			playerIndex = i
			break
		}
	}

	if !found {
		log.Printf("GameState: Attempted to remove player %s (%s) who was not found (or not ready).", player.Id, player.Name)
		return
	}

	state.Players = slices.Delete(state.Players, playerIndex, playerIndex+1)
	log.Printf("GameState: Player %s (%s) removed. Remaining players: %d", player.Id, player.Name, len(state.Players))

	delete(state.GuessedCorrectly, player.Id)

	wasHost := state.HostId == player.Id
	wasDrawer := state.IsActive && state.CurrentDrawerIdx == playerIndex

	if wasHost {
		if len(state.Players) > 0 {
			state.HostId = state.Players[0].Id
			log.Printf("GameState: Host %s (%s) left. New host assigned: %s (%s).", player.Name, player.Id, state.Players[0].Name, state.HostId)
		} else {
			state.HostId = ""
		}
	}

	state.broadcastPlayerUpdate()

	if len(state.Players) < minPlayersToStart {
		state.Phase = GamePhaseHandler(&GameOverHandler{})
	} else {
		if playerIndex < state.CurrentDrawerIdx {
			state.CurrentDrawerIdx--
		} else if playerIndex == state.CurrentDrawerIdx && len(state.Players) > 0 {
			state.CurrentDrawerIdx = (playerIndex - 1 + len(state.Players)) % len(state.Players)
		}

		allGuessed := state.checkAllGuessed()
		state.broadcastPlayerUpdate() // Send update *before* potentially ending turn

		if wasDrawer || allGuessed {
			log.Printf("GameState: Ending turn early due to player %s leaving (was drawer: %t, all guessed now: %t).", player.Name, wasDrawer, allGuessed)
			state.endTurn()
		}
	}
}
