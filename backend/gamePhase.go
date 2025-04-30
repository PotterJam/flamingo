package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"time"
)

var turnDuration = 59 * time.Second

const (
	minPlayersToStart = 2
)

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
	GamePhaseRoundFinished:   "RoundFinished",
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
	HandleTimeOut(gs *GameState) GamePhaseHandler // Some phases have timeouts, this is good enough for now but can be improved
}

type WaitingInLobbyHandler struct{}

func (p *WaitingInLobbyHandler) Phase() GamePhase {
	return GamePhaseWaitingInLobby
}

func (p *WaitingInLobbyHandler) StartPhase(gs *GameState) {
	return
}

func (p *WaitingInLobbyHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type == ClientStartGame && player.Id == gs.HostId {
		if len(gs.Players) < minPlayersToStart {
			gs.BroadcastSystemMessage("Game start aborted, not enough players.")
		} else if !gs.IsActive {
			gs.IsActive = true
			return GamePhaseHandler(&RoundSetupHandler{WordToPickFrom: nil})
		}
	}

	return GamePhaseHandler(p)
}

func (p *WaitingInLobbyHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}

// RoundSetupHandler Useless for now until adding word selection etc
type RoundSetupHandler struct {
	WordToPickFrom *[]string
}

func (p *RoundSetupHandler) Phase() GamePhase {
	return GamePhaseRoundSetup
}

func (p *RoundSetupHandler) StartPhase(gs *GameState) {
	gs.turnEndTime = time.Now().Add(10 * time.Second)
	gs.timerForTimeout = time.NewTimer(10 * time.Second)

	gs.CurrentDrawerIdx = (gs.CurrentDrawerIdx + 1) % len(gs.Players)
	newDrawer := gs.Players[gs.CurrentDrawerIdx]

	wordChoices := make([]string, 3)
	perms := rand.Perm(len(words))
	for i, r := range perms[:len(wordChoices)] {
		wordChoices[i] = words[r]
	}
	p.WordToPickFrom = &wordChoices

	turnPayloadBase := TurnSetupPayload{
		CurrentDrawerID: newDrawer.Id,
		Players:         gs.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.WordChoices = *p.WordToPickFrom
	log.Printf("GameState: Sending TurnSetup (with word choices) to drawer %s", newDrawer.Name)
	go newDrawer.SendMessage(TurnSetupResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	msgBytes := MustMarshal(Message{Type: TurnSetupResponse, Payload: json.RawMessage(MustMarshal(guesserPayload))})
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnSetup (no word choices) to %d guessers", len(playersToSendTo))
	go gs.Room.BroadcastToPlayers(msgBytes, playersToSendTo)

	gs.BroadcastSystemMessage(newDrawer.Name + " is choosing a word.")
	return
}

func (p *RoundSetupHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type != ClientSelectRoundWord || !gs.isDrawer(player) {
		return p
	}

	if len(gs.Players) < minPlayersToStart {
		log.Println("GameState: Cannot start next turn, less than minimum players.")
		return GamePhaseHandler(&GameOverHandler{})
	}

	var roundWordPayload SelectRoundWordPayload
	if err := json.Unmarshal(msg.Payload, &roundWordPayload); err != nil {
		player.SendError("Invalid guess format.")
		return p
	}

	// TODO: check that player hasn't picked a random word, make sure it's in the list of p.WordToPickFrom
	return GamePhaseHandler(&RoundInProgressHandler{Word: roundWordPayload.Word})
}

func (p *RoundSetupHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	word := (*p.WordToPickFrom)[rand.Intn(len(*p.WordToPickFrom))]
	return GamePhaseHandler(&RoundInProgressHandler{Word: word})
}

type RoundInProgressHandler struct {
	Word string
}

func (p *RoundInProgressHandler) Phase() GamePhase {
	return GamePhaseRoundInProgress
}

func (p *RoundInProgressHandler) StartPhase(gs *GameState) {
	gs.CorrectGuessTimes = make(map[string]time.Time)

	if gs.CurrentDrawerIdx < -1 || gs.CurrentDrawerIdx >= len(gs.Players) {
		log.Printf("GameState: Resetting invalid CurrentDrawerIdx (%d) before next turn.", gs.CurrentDrawerIdx)
		gs.CurrentDrawerIdx = -1
	}

	drawer := gs.Players[gs.CurrentDrawerIdx]

	gs.Word = p.Word
	now := time.Now()
	gs.TurnStartTime = now
	gs.turnEndTime = now.Add(turnDuration)
	gs.timerForTimeout = time.NewTimer(turnDuration)

	turnPayloadBase := TurnStartPayload{
		CurrentDrawerID: drawer.Id,
		WordLength:      len(gs.Word),
		Players:         gs.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = gs.Word
	log.Printf("GameState: Sending TurnStart (with word) to drawer %s", drawer.Name)
	go drawer.SendMessage(TurnStartResponse, drawerPayload)

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

	gs.BroadcastSystemMessage(drawer.Name + " is drawing!")
	return
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	if msg.Type == ClientGuess && !gs.isDrawer(player) {
		if _, alreadyGuessed := gs.CorrectGuessTimes[player.Id]; alreadyGuessed {
			return p
		}

		var guessPayload GuessPayload
		if err := json.Unmarshal(msg.Payload, &guessPayload); err != nil {
			player.SendError("Invalid guess format.")
			return p
		}

		correct := guessPayload.Guess == gs.Word

		if correct {
			gs.CorrectGuessTimes[player.Id] = time.Now()
			gs.BroadcastSystemMessage(player.Name + " guessed the word!")

			if gs.checkAllGuessed() {
				return GamePhaseHandler(&RoundFinishedHandler{})
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
	return p
}

func (p *RoundInProgressHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}

type RoundFinishedHandler struct{}

func (p *RoundFinishedHandler) Phase() GamePhase {
	return GamePhaseRoundFinished
}

func (p *RoundFinishedHandler) StartPhase(gs *GameState) {
	playerRoundScores := calculateRoundScores(gs)

	// Apply score deltas
	for _, player := range gs.Players {
		if delta, ok := playerRoundScores[player.Id]; ok {
			player.Score += delta
		}
	}

	finishDelay := 5 * time.Second
	gs.timerForTimeout = time.NewTimer(finishDelay)
	gs.turnEndTime = time.Now().Add(finishDelay)

	gs.BroadcastSystemMessage("Turn over! The word was: " + gs.Word)
	turnEndPayload := TurnEndPayload{
		CorrectWord: gs.Word,
		Players:     gs.getPlayerInfoList(),
		RoundScores: playerRoundScores,
	}
	turnEndMsgBytes := MustMarshal(Message{Type: TurnEndResponse, Payload: json.RawMessage(MustMarshal(turnEndPayload))})
	go gs.Room.Broadcast(turnEndMsgBytes)
}

func (p *RoundFinishedHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	return p
}

func (p *RoundFinishedHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	log.Println("GameState: Delay finished, attempting to start next turn.")

	gs.CorrectGuessTimes = make(map[string]time.Time)
	gs.Word = ""

	if gs.IsActive {
		return GamePhaseHandler(&RoundSetupHandler{WordToPickFrom: nil})
	} else {
		log.Println("GameState: GameState became inactive during turn delay, not starting next turn.")
		return GamePhaseHandler(&WaitingInLobbyHandler{})
	}
}

type GameOverHandler struct{}

func (p *GameOverHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *GameOverHandler) StartPhase(gs *GameState) {
	// todo
	return
}

func (p *GameOverHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return p
}

func (p *GameOverHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}

type ErrorHandler struct{}

func (p *ErrorHandler) Phase() GamePhase {
	return GamePhaseGameOver
}

func (p *ErrorHandler) StartPhase(gs *GameState) {
	// todo
	return
}

func (p *ErrorHandler) HandleMessage(gs *GameState, player *Player, msg Message) GamePhaseHandler {
	// todo
	return p
}

func (p *ErrorHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return p
}

// sendGameInfo sends the initial game state to a player
func (g *Game) sendGameInfo(player *Player) {
	state := g.GameState
	payload := GameInfoPayload{
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
	go player.SendMessage(GameInfoResponse, payload)
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
	payload := ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	msgBytes := MustMarshal(Message{Type: ChatResponse, Payload: json.RawMessage(MustMarshal(payload))})
	go g.Room.Broadcast(msgBytes)
}
