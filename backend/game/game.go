package game

import (
	"backend/messages"
	"log"
	"slices"
	"time"
)

type GameMessage struct {
	player *Player
	msg    messages.Message
}

type Game struct {
	GameHandler GamePhaseHandler
	GameState   *GameState
	Messages    chan GameMessage
}

func (g *Game) HandleEvents() {
	for {
		var timerChan <-chan time.Time
		g.GameState.mu.Lock()
		if g.GameState.timerForTimeout != nil {
			timerChan = g.GameState.timerForTimeout.C
		}
		g.GameState.mu.Unlock()

		var newHandler GamePhaseHandler
		select {
		case msg := <-g.Messages:
			g.GameState.mu.Lock()
			newHandler = g.GameHandler.HandleMessage(g.GameState, msg.player, msg.msg)

		case <-timerChan:
			g.GameState.mu.Lock()

			if g.GameState.timerForTimeout == nil {
				// We've had an update to the store that means we no longer want to respect the timeout, ignore
				continue
			}

			newHandler = g.GameHandler.HandleTimeOut(g.GameState)
		}

		g.updateHandler(newHandler)
		g.GameState.mu.Unlock()
	}
}

func (g *Game) updateHandler(newHandler GamePhaseHandler) {
	if newHandler.Phase() == g.GameHandler.Phase() {
		return
	}

	if g.GameState.timerForTimeout != nil {
		g.GameState.timerForTimeout.Stop()
		g.GameState.timerForTimeout = nil
	}

	g.GameHandler = newHandler

	// Don't block on start phase, as we still want to process stuff while it's starting
	go g.GameHandler.StartPhase(g.GameState)
}

func NewGame(b Broadcaster) *Game {
	handler := GamePhaseHandler(&WaitingInLobbyHandler{})

	return &Game{
		GameState: &GameState{
			Players:                      make([]*Player, 0, 10),
			HostId:                       "", // No host initially
			CurrentDrawerIdx:             -1,
			CorrectGuessTimes:            make(map[string]time.Time),
			Broadcaster:                  b,
			IsActive:                     false,
			timerForTimeout:              nil,
			TotalRounds:                  1, // Default to 1 round (each player draws once)
			CurrentRound:                 0,
			PlayersWhoHaveDrawnThisRound: make([]string, 0),
		},
		GameHandler: handler,
		Messages:    make(chan GameMessage, 5),
	}
}

func (g *Game) AddPlayer(player *Player) {
	state := g.GameState

	state.mu.Lock()
	defer state.mu.Unlock()

	// Avoid adding duplicates
	for _, p := range state.Players {
		if p.Id == player.Id {
			log.Printf("GameState: Player %s (%s) already marked as ready.", player.Id, player.Name)
			g.sendGameInfo(player)
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

	g.sendGameInfo(player)
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

	delete(g.GameState.CorrectGuessTimes, player.Id)

	wasHost := state.HostId == player.Id

	if wasHost {
		if len(state.Players) > 0 {
			state.HostId = state.Players[0].Id
			log.Printf("GameState: Host %s (%s) left. New host assigned: %s (%s).", player.Name, player.Id, state.Players[0].Name, state.HostId)
		} else {
			state.HostId = ""
		}
	}

	state.broadcastPlayerUpdate()

	wasDrawer := state.IsActive && state.CurrentDrawerIdx == playerIndex
	if len(state.Players) < minPlayersToStart {
		g.updateHandler(ackPhaseTransitionTo(&GameOverHandler{}))
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
			g.updateHandler(ackPhaseTransitionTo(&RoundFinishedHandler{}))
		}
	}
}
