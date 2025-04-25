package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"sync"
	"time"
)

const turnDuration = 60 * time.Second
const minPlayersToStart = 2

// Game represents the single, shared game session.
type Game struct {
	Players          []*Player
	HostID           string
	CurrentDrawerIdx int             // Index in Players slice of the current drawer (-1 if no game)
	Word             string          // The secret word for the current turn
	GuessedCorrectly map[string]bool // Set of player IDs who guessed correctly this turn
	Hub              *Hub
	mu               sync.Mutex  // Mutex to protect concurrent access to game state
	IsActive         bool        // Flag indicating if a round/turn is currently running
	turnTimer        *time.Timer // Timer for the current turn
	turnEndTime      time.Time   // When the current turn is scheduled to end
}

func NewGame(hub *Hub) *Game {
	log.Println("Game: Creating new shared game instance.")
	return &Game{
		Players:          make([]*Player, 0, 10),
		HostID:           "", // No host initially
		CurrentDrawerIdx: -1,
		GuessedCorrectly: make(map[string]bool),
		Hub:              hub,
		IsActive:         false,
	}
}

func (g *Game) PlayerIsReady(player *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	// Avoid adding duplicates
	for _, p := range g.Players {
		if p.ID == player.ID {
			log.Printf("Game: Player %s (%s) already marked as ready.", player.ID, player.Name)
			g.sendGameInfo(player)
			return
		}
	}

	g.Players = append(g.Players, player)
	log.Printf("Game: Player %s (%s) marked ready. Total ready players: %d", player.ID, player.Name, len(g.Players))

	// Assign host to the first player
	if len(g.Players) == 1 {
		g.HostID = player.ID
		log.Printf("Game: Player %s (%s) assigned as Host.", player.ID, player.Name)
	}

	g.sendGameInfo(player)
	g.broadcastPlayerUpdate()
}

func (g *Game) RemovePlayer(player *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	found := false
	playerIndex := -1
	for i, p := range g.Players {
		if p != nil && p.ID == player.ID {
			found = true
			playerIndex = i
			break
		}
	}

	if !found {
		log.Printf("Game: Attempted to remove player %s (%s) who was not found (or not ready).", player.ID, player.Name)
		return
	}

	g.Players = append(g.Players[:playerIndex], g.Players[playerIndex+1:]...)
	log.Printf("Game: Player %s (%s) removed. Remaining players: %d", player.ID, player.Name, len(g.Players))

	delete(g.GuessedCorrectly, player.ID)

	wasHost := g.HostID == player.ID
	wasDrawer := g.IsActive && g.CurrentDrawerIdx == playerIndex

	if wasHost {
		if len(g.Players) > 0 {
			g.HostID = g.Players[0].ID
			log.Printf("Game: Host %s (%s) left. New host assigned: %s (%s).", player.Name, player.ID, g.Players[0].Name, g.HostID)
		} else {
			g.HostID = ""
			log.Println("Game: Host left. No players remaining.")
		}
	}

	if !g.IsActive {
		g.broadcastPlayerUpdate() // Includes new host if changed
		return
	}

	if len(g.Players) < minPlayersToStart {
		log.Println("Game: Player count dropped below minimum. Ending game.")
		g.endGame("Not enough players.")
		g.broadcastPlayerUpdate() // Includes new host if changed
	} else {
		if playerIndex < g.CurrentDrawerIdx {
			g.CurrentDrawerIdx--
		} else if playerIndex == g.CurrentDrawerIdx && len(g.Players) > 0 {
			g.CurrentDrawerIdx = (playerIndex - 1 + len(g.Players)) % len(g.Players)
		}

		allGuessed := g.checkAllGuessed()
		g.broadcastPlayerUpdate() // Send update *before* potentially ending turn

		if wasDrawer || allGuessed {
			log.Printf("Game: Ending turn early due to player %s leaving (was drawer: %t, all guessed now: %t).", player.Name, wasDrawer, allGuessed)
			g.endTurn()
		}
	}
}

// startGame initializes the first turn
func (g *Game) startGame() {
	log.Println("Game: startGame() called.")
	if len(g.Players) < minPlayersToStart {
		log.Println("Game: startGame() aborted, less than minimum players.")
		return
	}
	if g.IsActive {
		log.Println("Game: startGame() aborted, game already active.")
		return
	}

	log.Println("Game: Setting IsActive=true and starting first turn.")
	g.IsActive = true
	g.CurrentDrawerIdx = -1
	g.nextTurn()
}

// endGame resets the game state (e.g., not enough players)
func (g *Game) endGame(reason string) {
	log.Printf("Game: endGame() called. Reason: %s", reason)
	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}
	g.IsActive = false
	g.CurrentDrawerIdx = -1
	g.Word = ""
	g.GuessedCorrectly = make(map[string]bool)
	g.turnEndTime = time.Time{}
	g.BroadcastSystemMessage("Game Over: " + reason)
}

// nextTurn selects next drawer, picks word, starts timer, notifies clients
func (g *Game) nextTurn() {
	log.Println("Game: nextTurn() called.")
	if !g.IsActive {
		log.Println("Game: nextTurn() called but game is not active. Aborting.")
		return
	}
	if len(g.Players) < minPlayersToStart {
		log.Println("Game: Cannot start next turn, less than minimum players.")
		g.endGame("Not enough players.")
		g.broadcastPlayerUpdate()
		return
	}

	if g.turnTimer != nil {
		g.turnTimer.Stop()
	}

	if g.CurrentDrawerIdx < -1 || g.CurrentDrawerIdx >= len(g.Players) {
		log.Printf("Game: Resetting invalid CurrentDrawerIdx (%d) before next turn.", g.CurrentDrawerIdx)
		g.CurrentDrawerIdx = -1
	}
	g.CurrentDrawerIdx = (g.CurrentDrawerIdx + 1) % len(g.Players)
	newDrawer := g.Players[g.CurrentDrawerIdx]

	g.Word = words[rand.Intn(len(words))]
	g.GuessedCorrectly = make(map[string]bool)

	g.turnEndTime = time.Now().Add(turnDuration)
	log.Printf("Game: Setting turn timer for %v.", turnDuration)
	g.turnTimer = time.AfterFunc(turnDuration, func() {
		log.Printf("Game: Turn timer expired callback initiated for drawer %s (%s), word '%s'", newDrawer.ID, newDrawer.Name, g.Word)
		g.mu.Lock()
		if g.isDrawer(newDrawer) {
			log.Println("Game: Timer expired, calling endTurn().")
			g.endTurn()
		} else {
			log.Println("Game: Timer expired but state changed, ignoring timer.")
		}
		g.mu.Unlock()
	})

	log.Printf("Game: Starting turn. Drawer: %s (%s), Word: %s, Ends At: %v", newDrawer.ID, newDrawer.Name, g.Word, g.turnEndTime.Format(time.Kitchen))

	turnPayloadBase := TurnStartPayload{
		CurrentDrawerID: newDrawer.ID,
		WordLength:      len(g.Word),
		Players:         g.getPlayerInfoList(), // Assumes lock held
		TurnEndTime:     g.turnEndTime.UnixMilli(),
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = g.Word
	log.Printf("Game: Sending TurnStart (with word) to drawer %s", newDrawer.Name)
	go newDrawer.SendMessage(TurnStartResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	msgBytes := mustMarshal(Message{Type: TurnStartResponse, Payload: json.RawMessage(mustMarshal(guesserPayload))})
	playersToSendTo := make([]*Player, 0, len(g.Players)-1)
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("Game: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go g.Hub.BroadcastToPlayers(msgBytes, playersToSendTo)

	g.BroadcastSystemMessage(*newDrawer.Name + " is drawing!")
}

func (g *Game) endTurn() {
	log.Println("Game: endTurn() called.")
	if !g.IsActive {
		log.Println("Game: Attempted to end turn, but game is not active.")
		return
	}

	log.Printf("Game: Ending turn for word '%s'.", g.Word)

	if g.turnTimer != nil {
		g.turnTimer.Stop()
		g.turnTimer = nil
	}

	g.BroadcastSystemMessage("Turn over! The word was: " + g.Word)
	turnEndPayload := TurnEndPayload{CorrectWord: g.Word}
	turnEndMsgBytes := mustMarshal(Message{Type: TurnEndResponse, Payload: json.RawMessage(mustMarshal(turnEndPayload))})
	log.Println("Game: Broadcasting TurnEnd message.")
	go g.Hub.Broadcast(turnEndMsgBytes)

	log.Println("Game: Scheduling next turn.")
	time.AfterFunc(3*time.Second, func() {
		log.Println("Game: Delay finished, attempting to start next turn.")
		g.mu.Lock()
		if g.IsActive {
			g.nextTurn()
		} else {
			log.Println("Game: Game became inactive during turn delay, not starting next turn.")
		}
		g.mu.Unlock()
	})
}

// sendGameInfo sends the initial game state to a player
func (g *Game) sendGameInfo(player *Player) {
	payload := GameInfoPayload{
		YourID:       player.ID,
		Players:      g.getPlayerInfoList(),
		HostID:       g.HostID,
		IsGameActive: g.IsActive,
	}

	if g.IsActive && g.CurrentDrawerIdx >= 0 && g.CurrentDrawerIdx < len(g.Players) {
		payload.CurrentDrawerID = g.Players[g.CurrentDrawerIdx].ID
		payload.WordLength = len(g.Word)
		payload.TurnEndTime = g.turnEndTime.UnixMilli()
		if player.ID == payload.CurrentDrawerID {
			payload.Word = g.Word
		}
	}
	log.Printf("Game: Sending game info to player %s (%s). Active: %t, Host: %s", player.ID, player.Name, payload.IsGameActive, g.HostID)
	go player.SendMessage(GameInfoResponse, payload)
}

func (g *Game) HandleMessage(sender *Player, msg Message) {
	if msg.Type == ClientRegisterUser {
		if sender.Name != nil {
			ParseAndSetName(sender, msg)
		} else {
			log.Printf("Player %s (%s) sent setName message after name was already set. Ignoring.", sender.ID, sender.Name)
		}
	} else if sender.Name == nil {
		log.Printf("Player %s (%s) sent message type %s before setting name.", sender.ID, sender.Name, msg.Type)
		sender.SendError("Please set your name first.")
	} else {
		switch msg.Type {
		case ClientDrawEvent:
			g.HandleDrawEvent(sender, msg.Payload)
		case ClientGuess:
			g.HandleGuess(sender, msg.Payload)
		case ClientStartGame:
			g.HandleStartGame(sender)
			log.Printf("Game: Received unhandled message type '%s' from player %s (%s)", msg.Type, sender.ID, sender.Name)
		}
	}
}

func ParseAndSetName(sender *Player, msg Message) {
	var namePayload SetNamePayload
	if err := json.Unmarshal(msg.Payload, &namePayload); err == nil {
		trimmedName := namePayload.Name
		if trimmedName != "" && len(trimmedName) <= 20 {
			sender.Name = &trimmedName
			log.Printf("Player %s set name to %s", sender.ID, sender.Name)
			log.Printf("Player %s (%s) sending PlayerReady signal to Hub", sender.ID, sender.Name)
			sender.Hub.PlayerReady <- sender
		} else {
			sender.SendError("Invalid name. Must be 1-20 characters.")
		}
	} else {
		log.Printf("Player %s (%s): Error unmarshalling SetName payload: %v", sender.ID, sender.Name, err)
		sender.SendError("Invalid name payload.")
	}
}

func (g *Game) HandleStartGame(sender *Player) {
	g.mu.Lock()
	defer g.mu.Unlock()

	log.Printf("Game: Received StartGame request from %s (%s)", sender.ID, sender.Name)

	if sender.ID != g.HostID {
		log.Printf("Game: StartGame denied. Player %s is not the host (%s).", sender.Name, g.HostID)
		sender.SendError("Only the host can start the game.")
		return
	}
	if g.IsActive {
		log.Println("Game: StartGame denied. Game is already active.")
		sender.SendError("The game is already in progress.")
		return
	}
	if len(g.Players) < minPlayersToStart {
		log.Printf("Game: StartGame denied. Not enough players (%d/%d).", len(g.Players), minPlayersToStart)
		sender.SendError("Not enough players to start the game (minimum " + string(minPlayersToStart+'0') + ").")
		return
	}

	log.Printf("Game: Host %s (%s) is starting the game.", sender.Name, sender.ID)
	g.startGame()
}

// HandleDrawEvent processes drawing data and forwards it.
func (g *Game) HandleDrawEvent(sender *Player, payload json.RawMessage) {
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

	drawMsgBytes := mustMarshal(Message{Type: DrawEventBroadcastResponse, Payload: payload})
	playersToSendTo := make([]*Player, 0, len(g.Players)-1)
	for _, p := range g.Players {
		if p != nil && p.ID != sender.ID {
			playersToSendTo = append(playersToSendTo, p)
		}
	}

	go g.Hub.BroadcastToPlayers(drawMsgBytes, playersToSendTo)
}

func (g *Game) HandleGuess(sender *Player, payload json.RawMessage) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if !g.IsActive {
		return
	}

	if g.isDrawer(sender) {
		sender.SendError("The drawer cannot make guesses.")
		return
	}

	if g.GuessedCorrectly[sender.ID] {
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
		log.Printf("Game: Guess '%s' by %s (%s) is CORRECT!", guessPayload.Guess, sender.Name, sender.ID)
		g.GuessedCorrectly[sender.ID] = true

		correctPayload := PlayerGuessedCorrectlyPayload{PlayerID: sender.ID}
		msgBytes := mustMarshal(Message{Type: PlayerGuessedCorrectlyResponse, Payload: json.RawMessage(mustMarshal(correctPayload))})
		go g.Hub.Broadcast(msgBytes)

		if g.checkAllGuessed() {
			log.Println("Game: All players have guessed correctly.")
			g.endTurn() // Assumes lock held
		}
	} else {
		g.BroadcastChatMessage(*sender.Name, guessPayload.Guess) // Assumes lock held
	}
}

func (g *Game) checkAllGuessed() bool {
	totalPlayers := len(g.Players)

	if !g.IsActive || totalPlayers < minPlayersToStart || g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}
	correctCount := 0
	for i, p := range g.Players {
		if i != g.CurrentDrawerIdx && g.GuessedCorrectly[p.ID] {
			correctCount++
		}
	}

	requiredCorrect := totalPlayers - 1
	return correctCount == requiredCorrect
}

func (g *Game) broadcastPlayerUpdate() {
	payload := PlayerUpdatePayload{
		Players: g.getPlayerInfoList(), // Assumes lock held
		HostID:  g.HostID,
	}
	msgBytes := mustMarshal(Message{Type: PlayerUpdateResponse, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

func (g *Game) BroadcastChatMessage(senderName, message string) {
	payload := ChatPayload{SenderName: senderName, Message: message, IsSystem: false}
	msgBytes := mustMarshal(Message{Type: ChatResponse, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

func (g *Game) BroadcastSystemMessage(message string) {
	payload := ChatPayload{SenderName: "System", Message: message, IsSystem: true}
	msgBytes := mustMarshal(Message{Type: ChatResponse, Payload: json.RawMessage(mustMarshal(payload))})
	go g.Hub.Broadcast(msgBytes)
}

func (g *Game) getPlayerInfoList() []PlayerInfo {
	infoList := make([]PlayerInfo, 0, len(g.Players))
	for _, p := range g.Players {
		if p != nil {
			infoList = append(infoList, PlayerInfo{
				ID:                  p.ID,
				Name:                *p.Name,
				IsHost:              p.ID == g.HostID,
				HasGuessedCorrectly: g.GuessedCorrectly[p.ID],
			})
		} else {
			log.Printf("Game Error: Found nil player in g.Players during getPlayerInfoList")
		}
	}
	return infoList
}

func (g *Game) isDrawer(p *Player) bool {
	if !g.IsActive {
		return false
	}

	if g.CurrentDrawerIdx < 0 || g.CurrentDrawerIdx >= len(g.Players) {
		return false
	}

	return g.Players[g.CurrentDrawerIdx].ID == p.ID
}
