package main

import (
	"encoding/json"
	"log"
	"time"
)

const turnDuration = 60 * time.Second
const minPlayersToStart = 2

type GamePhase int

const (
	GamePhaseWaitingInLobby GamePhase = iota
	GamePhaseRoundSetup
	GamePhaseRoundInProgress
	GamePhaseGameOver
	GamePhaseError
)

var stateName = map[GamePhase]string{
	GamePhaseWaitingInLobby:  "WaitingInLobby",
	GamePhaseRoundSetup:      "RoundSetup",
	GamePhaseRoundInProgress: "RoundInProgress",
	GamePhaseGameOver:        "GameOver",
	GamePhaseError:           "Error",
}

func (ss GamePhase) String() string {
	return stateName[ss]
}

type GamePhaseHandler interface {
	Phase() GamePhase
	StartPhase(gs *GameState)
	HandleMessage(gs *GameState, playerID *Player, msg Message) GamePhaseHandler
}

type WaitingInLobbyHandler struct{}

func (p *WaitingInLobbyHandler) Phase() GamePhase {
	return GamePhaseWaitingInLobby
}

func (p *WaitingInLobbyHandler) StartPhase(gs *GameState) {
	if !gs.IsActive {
		return
	}

}

func (p *WaitingInLobbyHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type == ClientStartGame && player.Id == gs.HostId {
		if len(gs.Players) < minPlayersToStart {
			gs.BroadcastSystemMessage("Game start aborted, not enough players.")
		} else if !gs.IsActive {
			gs.IsActive = true
			gs.CurrentDrawerIdx = 0
			return GamePhaseHandler(&RoundSetupHandler{})
		}
	}

	return GamePhaseHandler(p)
}

type RoundSetupHandler struct{}

func (p *RoundSetupHandler) Phase() GamePhase {
	return GamePhaseRoundSetup
}

func (p *RoundSetupHandler) StartPhase(gs *GameState) {
	// Pick the new drawer
	// Send updated player info
	// Get 3 words
	// Send them to the new drawer
}

func (p *RoundSetupHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {

	//if len(gs.Players) < minPlayersToStart {
	//	log.Println("GameState: Cannot start next turn, less than minimum players.")
	//	gs.resetGameState("Not enough players.")
	//	gs.broadcastPlayerUpdate()
	//	return
	//}
	//
	//if gs.turnTimer != nil {
	//	gs.turnTimer.Stop()
	//}
	//
	//if gs.CurrentDrawerIdx < -1 || gs.CurrentDrawerIdx >= len(gs.Players) {
	//	log.Printf("GameState: Resetting invalid CurrentDrawerIdx (%d) before next turn.", gs.CurrentDrawerIdx)
	//	gs.CurrentDrawerIdx = -1
	//}
	//gs.CurrentDrawerIdx = (gs.CurrentDrawerIdx + 1) % len(gs.Players)
	//newDrawer := gs.Players[gs.CurrentDrawerIdx]
	//
	//gs.Word = words[rand.Intn(len(words))]
	//gs.GuessedCorrectly = make(map[string]bool)
	//
	//gs.turnEndTime = time.Now().Add(turnDuration)
	//log.Printf("GameState: Setting turn timer for %v.", turnDuration)
	//gs.turnTimer = time.AfterFunc(turnDuration, func() {
	//	log.Printf("GameState: Turn timer expired callback initiated for drawer %s (%s), word '%s'", newDrawer.Id, newDrawer.Name, gs.Word)
	//	gs.mu.Lock()
	//	if gs.isDrawer(newDrawer) {
	//		log.Println("GameState: Timer expired, calling endTurn().")
	//		gs.endTurn()
	//	} else {
	//		log.Println("GameState: Timer expired but state changed, ignoring timer.")
	//	}
	//	gs.mu.Unlock()
	//})
	//
	//log.Printf("GameState: Starting turn. Drawer: %s (%s), Word: %s, Ends At: %v", newDrawer.Id, newDrawer.Name, gs.Word, gs.turnEndTime.Format(time.Kitchen))
	//
	//turnPayloadBase := TurnStartPayload{
	//	CurrentDrawerID: newDrawer.Id,
	//	WordLength:      len(gs.Word),
	//	Players:         gs.getPlayerInfoList(), // Assumes lock held
	//	TurnEndTime:     gs.turnEndTime.UnixMilli(),
	//}
	//
	//drawerPayload := turnPayloadBase
	//drawerPayload.Word = gs.Word
	//log.Printf("GameState: Sending TurnStart (with word) to drawer %s", newDrawer.Name)
	//go newDrawer.SendMessage(TurnStartResponse, drawerPayload)
	//
	//guesserPayload := turnPayloadBase
	//msgBytes := MustMarshal(Message{Type: TurnStartResponse, Payload: json.RawMessage(MustMarshal(guesserPayload))})
	//playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	//for i, p := range gs.Players {
	//	if i != gs.CurrentDrawerIdx {
	//		playersToSendTo = append(playersToSendTo, p)
	//	}
	//}
	//log.Printf("GameState: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	//go gs.Room.BroadcastToPlayers(msgBytes, playersToSendTo)
	//
	//gs.BroadcastSystemMessage(newDrawer.Name + " is drawing!")

	return gs.Phase
}

type RoundInProgressHandler struct{}

func (p *RoundInProgressHandler) Phase() GamePhase {
	return GamePhaseRoundInProgress
}

func (p *RoundInProgressHandler) StartPhase(gs *GameState) {
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	return gs.Phase
}

type GameOverHandler struct{}

func (p *GameOverHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *GameOverHandler) StartPhase(gs *GameState) {
	if !gs.IsActive {
		return
	}

}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	return gs.Phase
}

type ErrorHandler struct{}

func (p *ErrorHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *ErrorHandler) StartPhase(gs *GameState) {
}

func (p *ErrorHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	return gs.Phase
}

func (g *GameState) endTurn() {
	log.Println("GameState: endTurn() called.")
	if !g.IsActive {
		log.Println("GameState: Attempted to end turn, but game is not active.")
		return
	}

	log.Printf("GameState: Ending turn for word '%s'.", g.Word)

	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}

	g.BroadcastSystemMessage("Turn over! The word was: " + g.Word)
	turnEndPayload := TurnEndPayload{CorrectWord: g.Word}
	turnEndMsgBytes := MustMarshal(Message{Type: TurnEndResponse, Payload: json.RawMessage(MustMarshal(turnEndPayload))})
	log.Println("GameState: Broadcasting TurnEnd message.")
	go g.Room.Broadcast(turnEndMsgBytes)

	log.Println("GameState: Scheduling next turn.")
	time.AfterFunc(3*time.Second, func() {
		log.Println("GameState: Delay finished, attempting to start next turn.")
		g.mu.Lock()
		if g.IsActive {
			g.nextTurn()
		} else {
			log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		}
		g.mu.Unlock()
	})
}

// sendGameInfo sends the initial game state to a player
func (g *GameState) sendGameInfo(player *Player) {
	payload := GameInfoPayload{
		GamePhase:    g.Phase.Phase().String(),
		YourID:       player.Id,
		Players:      g.getPlayerInfoList(),
		HostID:       g.HostId,
		IsGameActive: g.IsActive,
	}

	if g.IsActive && g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) {
		payload.CurrentDrawerID = g.Players[g.CurrentDrawerIdx].Id
		payload.WordLength = len(g.Word)
		payload.TurnEndTime = g.turnEndTime.UnixMilli()
		if player.Id == payload.CurrentDrawerID {
			payload.Word = g.Word
		}
	}
	log.Printf("GameState: Sending game info to player %s (%s). Active: %t, Host: %s", player.Id, player.Name, payload.IsGameActive, g.HostId)
	go player.SendMessage(GameInfoResponse, payload)
}

func (g *GameState) HandleMessage(sender *Player, msg Message) {
	g.Phase.HandleMessage(g, sender, msg)
}

func (g *GameState) HandleStartGame(sender *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

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

	log.Printf("GameState: Host %s (%s) is starting the game.", sender.Name, sender.Id)
	g.startGame()
}

// HandleDrawEvent processes drawing data and forwards it.
func (g *GameState) HandleDrawEvent(sender *Player, payload json.RawMessage) {
	if !g.IsActive {
		return
	}

	g.mu.Lock()
	defer g.mu.Unlock()

	isDrawer := g.isDrawer(sender)
	if !isDrawer {
		sender.SendError("Only the current drawer can send drawing events.")
		return
	}

	drawMsgBytes := MustMarshal(Message{Type: DrawEventBroadcastResponse, Payload: payload})
	playersToSendTo := make([]*Player, 0, len(g.Players)-1)
	for _, p := range g.Players {
		if p != nil && p.Id != sender.Id {
			playersToSendTo = append(playersToSendTo, p)
		}
	}

	go g.Room.BroadcastToPlayers(drawMsgBytes, playersToSendTo)
}

func (g *GameState) HandleGuess(sender *Player, payload json.RawMessage) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if !g.IsActive {
		return
	}

	if g.isDrawer(sender) {
		sender.SendError("The drawer cannot make guesses.")
		return
	}

	if g.GuessedCorrectly[sender.Id] {
		sender.SendError("You already guessed the word correctly this turn.")
		return
	}

	var guessPayload GuessPayload
	if err := json.Unmarshal(payload, &guessPayload); err != nil {
		sender.SendError("Invalid guess format.")
		return
	}

	correct := guessPayload.Guess == g.Word

	if correct {
		log.Printf("GameState: Guess '%s' by %s (%s) is CORRECT!", guessPayload.Guess, sender.Name, sender.Id)
		g.GuessedCorrectly[sender.Id] = true

		correctPayload := PlayerGuessedCorrectlyPayload{PlayerID: sender.Id}
		msgBytes := MustMarshal(Message{Type: PlayerGuessedCorrectlyResponse, Payload: json.RawMessage(MustMarshal(correctPayload))})
		go g.Room.Broadcast(msgBytes)

		if g.checkAllGuessed() {
			log.Println("GameState: All players have guessed correctly.")
			g.endTurn() // Assumes lock held
		}
	} else {
		g.BroadcastChatMessage(sender.Name, guessPayload.Guess) // Assumes lock held
	}
}

func (g *GameState) checkAllGuessed() bool {
	totalPlayers := len(g.Players)

	if !g.IsActive || totalPlayers < minPlayersToStart || g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}
	correctCount := 0
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx && g.GuessedCorrectly[p.Id] {
			correctCount++
		}
	}

	requiredCorrect := totalPlayers - 1
	return correctCount == requiredCorrect
}

func (g *GameState) BroadcastChatMessage(senderName, message string) {
	payload := ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	msgBytes := MustMarshal(Message{Type: ChatResponse, Payload: json.RawMessage(MustMarshal(payload))})
	go g.Room.Broadcast(msgBytes)
}
