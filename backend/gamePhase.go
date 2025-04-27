package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"time"
)

var turnDuration = 60 * time.Second

const minPlayersToStart = 2

type GamePhase int

const (
	GamePhaseWaitingInLobby GamePhase = iota
	GamePhaseRoundSetup
	GamePhaseRoundInProgress
	GamePhaseRoundFinished
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
	StartPhase(gs *GameState) *time.Duration
	HandleMessage(gs *GameState, playerID *Player, msg Message) GamePhaseHandler
	HandleTimeOut(gs *GameState) GamePhaseHandler // Some phases have timeouts, this is good enough for now but can be improved
}

type WaitingInLobbyHandler struct{}

func (p *WaitingInLobbyHandler) Phase() GamePhase {
	return GamePhaseWaitingInLobby
}

func (p *WaitingInLobbyHandler) StartPhase(gs *GameState) *time.Duration {
	if !gs.IsActive {
		return nil
	}

	return nil
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

func (p *WaitingInLobbyHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
}

type RoundSetupHandler struct{}

func (p *RoundSetupHandler) Phase() GamePhase {
	return GamePhaseRoundSetup
}

func (p *RoundSetupHandler) StartPhase(gs *GameState) *time.Duration {
	// Pick the new drawer
	// Send updated player info
	// Get 3 words
	// Send them to the new drawer
	return nil
}

func (p *RoundSetupHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if len(gs.Players) < minPlayersToStart {
		log.Println("GameState: Cannot start next turn, less than minimum players.")
		gs.resetGameState("Not enough players.")
		gs.broadcastPlayerUpdate()
		return gs.Phase
	}

	if gs.turnTimer != nil {
		gs.turnTimer = nil
	}

	return gs.Phase
}

func (p *RoundSetupHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
}

type RoundInProgressHandler struct{}

func (p *RoundInProgressHandler) Phase() GamePhase {
	return GamePhaseRoundInProgress
}

func (p *RoundInProgressHandler) StartPhase(gs *GameState) *time.Duration {
	gs.GuessedCorrectly = make(map[string]bool)

	if gs.CurrentDrawerIdx < -1 || gs.CurrentDrawerIdx >= len(gs.Players) {
		log.Printf("GameState: Resetting invalid CurrentDrawerIdx (%d) before next turn.", gs.CurrentDrawerIdx)
		gs.CurrentDrawerIdx = -1
	}
	gs.CurrentDrawerIdx = (gs.CurrentDrawerIdx + 1) % len(gs.Players)
	newDrawer := gs.Players[gs.CurrentDrawerIdx]

	gs.Word = words[rand.Intn(len(words))]

	turnPayloadBase := TurnStartPayload{
		CurrentDrawerID: newDrawer.Id,
		WordLength:      len(gs.Word),
		Players:         gs.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = gs.Word
	log.Printf("GameState: Sending TurnStart (with word) to drawer %s", newDrawer.Name)
	go newDrawer.SendMessage(TurnStartResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	msgBytes := MustMarshal(Message{Type: TurnStartResponse, Payload: json.RawMessage(MustMarshal(guesserPayload))})
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go gs.Room.BroadcastToPlayers(msgBytes, playersToSendTo)

	gs.BroadcastSystemMessage(newDrawer.Name + " is drawing!")
	return &turnDuration
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type == ClientGuess && !gs.isDrawer(player) {
		if gs.GuessedCorrectly[player.Id] {
			player.SendError("You already guessed the word correctly this turn.")
			return gs.Phase
		}

		var guessPayload GuessPayload
		if err := json.Unmarshal(msg.Payload, &guessPayload); err != nil {
			player.SendError("Invalid guess format.")
			return gs.Phase
		}

		correct := guessPayload.Guess == gs.Word

		if correct {
			gs.GuessedCorrectly[player.Id] = true

			correctPayload := PlayerGuessedCorrectlyPayload{PlayerID: player.Id}
			msgBytes := MustMarshal(Message{Type: PlayerGuessedCorrectlyResponse, Payload: MustMarshal(correctPayload)})
			go gs.Room.Broadcast(msgBytes)

			if gs.checkAllGuessed() {
				return GamePhaseHandler(&RoundSetupHandler{})
			}
		} else {
			gs.BroadcastChatMessage(player.Name, guessPayload.Guess)
		}
	} else if msg.Type == ClientDrawEvent && gs.isDrawer(player) {
		drawMsgBytes := MustMarshal(Message{Type: DrawEventBroadcastResponse, Payload: msg.Payload})
		playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
		for _, p := range gs.Players {
			if p != nil && p.Id != player.Id {
				playersToSendTo = append(playersToSendTo, p)
			}
		}

		go gs.Room.BroadcastToPlayers(drawMsgBytes, playersToSendTo)
	}
	return gs.Phase
}

func (p *RoundInProgressHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
}

type RoundFinishedHandler struct{}

func (p *RoundFinishedHandler) Phase() GamePhase {
	return GamePhaseRoundFinished
}

func (p *RoundFinishedHandler) StartPhase(gs *GameState) *time.Duration {
	if gs.turnTimer != nil {
		gs.turnTimer.Stop()
		gs.turnTimer = nil
	}

	gs.BroadcastSystemMessage("Turn over! The word was: " + gs.Word)
	turnEndPayload := TurnEndPayload{CorrectWord: gs.Word}
	turnEndMsgBytes := MustMarshal(Message{Type: TurnEndResponse, Payload: json.RawMessage(MustMarshal(turnEndPayload))})
	go gs.Room.Broadcast(turnEndMsgBytes)

	time.AfterFunc(3*time.Second, func() {
		log.Println("GameState: Delay finished, attempting to start next turn.")
		if gs.IsActive {
			gs.nextTurn()
		} else {
			log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		}
	})
	return nil
}

func (p *RoundFinishedHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return gs.Phase
}

func (p *RoundFinishedHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
}

type GameOverHandler struct{}

func (p *GameOverHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *GameOverHandler) StartPhase(gs *GameState) *time.Duration {
	// todo
	return nil
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return gs.Phase
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
}

type ErrorHandler struct{}

func (p *ErrorHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *ErrorHandler) StartPhase(gs *GameState) *time.Duration {
	// todo
	return nil
}

func (p *ErrorHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return gs.Phase
}

func (p *ErrorHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return gs.Phase
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
