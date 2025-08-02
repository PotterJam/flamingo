package game

import (
	"backend/messages"
	"encoding/json"
	"log"
	"strings"
	"time"
)

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
	gs.turnEndTime = now.Add(gs.RoundDuration)
	gs.timerForTimeout = time.NewTimer(gs.RoundDuration)

	gs.setupHintTimers()

	turnPayloadBase := messages.TurnStartPayload{
		GamePhase:       p.Phase().String(),
		CurrentDrawerID: gs.Players[gs.CurrentDrawerIdx].Id,
		WordOutline:     generateWordOutline(gs.Word),
		Players:         gs.getPlayerInfoList(),
		TurnEndTime:     gs.turnEndTime.UnixMilli(),
		TotalRounds:     gs.TotalRounds,
		CurrentRound:    gs.CurrentRound,
	}

	drawerPayload := turnPayloadBase
	drawerPayload.Word = gs.Word
	log.Printf("GameState: Sending TurnStart (with word) to drawer %s", drawer.Name)
	go drawer.SendMessage(messages.TurnStartResponse, drawerPayload)

	guesserPayload := turnPayloadBase
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for i, p := range gs.Players {
		if i != gs.CurrentDrawerIdx {
			playersToSendTo = append(playersToSendTo, p)
		}
	}
	log.Printf("GameState: Sending TurnStart (no word) to %d guessers", len(playersToSendTo))
	go gs.Broadcaster.BroadcastToPlayers(messages.TurnStartResponse, guesserPayload, playersToSendTo)

	gs.BroadcastSystemMessage(drawer.Name + " is drawing!")
	return
}

func (p *RoundInProgressHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	if msg.Type == messages.ClientChat {
		var chatPayload messages.ClientChatPayload
		if err := json.Unmarshal(msg.Payload, &chatPayload); err != nil {
			player.SendError("Invalid chat format.")
			return p
		}
		gs.BroadcastChatMessage(player.Name, chatPayload.Message)
		return p
	}

	if msg.Type == messages.ClientGuess && !gs.isDrawer(player) {
		// If player has already guessed correctly they should be sending chat messages
		if _, alreadyGuessed := gs.CorrectGuessTimes[player.Id]; alreadyGuessed {
			return p
		}

		var guessPayload messages.GuessPayload
		if err := json.Unmarshal(msg.Payload, &guessPayload); err != nil {
			player.SendError("Invalid guess format.")
			return p
		}

		correct := strings.EqualFold(guessPayload.Guess, gs.Word)

		if !correct {
			gs.BroadcastChatMessage(player.Name, guessPayload.Guess)
			return p
		}

		gs.CorrectGuessTimes[player.Id] = time.Now()
		gs.BroadcastSystemMessage(player.Name + " guessed the word!")

		go player.SendMessage(messages.WordRevealResponse, messages.WordRevealPayload{
			Word: gs.Word,
		})

		playersToNotify := gs.allOtherPlayers(player)
		go gs.Broadcaster.BroadcastToPlayers(messages.PlayerCorrectResponse, messages.PlayerCorrectPayload{
			PlayerID:   player.Id,
			PlayerName: player.Name,
		}, playersToNotify)

		gs.broadcastPlayerUpdate()

		if gs.checkAllGuessed() {
			return ackPhaseTransitionTo(&DelayHandler{
				NextPhase:     &RoundScoreDisplayHandler{},
				DelayDuration: 1 * time.Second,
				CurrentPhase:  GamePhaseRoundInProgress,
				DelayMessage:  "Starting 1-second delay before score display (all players guessed)",
			})
		}

		return p
	}

	if msg.Type == messages.ClientDrawEvent && gs.isDrawer(player) {
		var drawPayload messages.DrawEventPayload
		if err := json.Unmarshal(msg.Payload, &drawPayload); err != nil {
			player.SendError("Invalid draw payload format.")
			return p
		}

		if drawPayload.EventType == "start" {
			newPathStack := make([]messages.DrawEventPayload, 0)
			gs.Canvas.PathStack = append(gs.Canvas.PathStack, &newPathStack)
			gs.Canvas.Actions = append(gs.Canvas.Actions, "path")
		}

		ds := gs.Canvas.PathStack[len(gs.Canvas.PathStack)-1]
		*ds = append(*ds, messages.DrawEventPayload{
			EventType: drawPayload.EventType,
			X:         drawPayload.X,
			Y:         drawPayload.Y,
			Color:     drawPayload.Color,
			LineWidth: drawPayload.LineWidth,
		})

		gs.HandleRasterDrawEvent(drawPayload)

		playersToSendTo := gs.allOtherPlayers(player)
		go gs.Broadcaster.BroadcastToPlayers(messages.DrawEventBroadcastResponse, msg.Payload, playersToSendTo)
		return p
	}

	if msg.Type == messages.ClientDrawPathUndo && gs.isDrawer(player) && len(gs.Canvas.PathStack) > 0 && len(gs.Canvas.Actions) > 0 {
		lastAction := gs.Canvas.Actions[len(gs.Canvas.Actions)-1]

		if lastAction == "fill" {
			gs.Canvas.Actions = gs.Canvas.Actions[:len(gs.Canvas.Actions)-1]
			return p
		}

		allButLatest := gs.Canvas.PathStack[:len(gs.Canvas.PathStack)-1]

		paths := make([]messages.DrawEventPayload, 0)
		for _, ds := range allButLatest {
			for _, p := range *ds {
				paths = append(paths, p)
			}
		}

		gs.Canvas.PathStack = gs.Canvas.PathStack[:len(gs.Canvas.PathStack)-1]

		go gs.Broadcaster.Broadcast(messages.CanvasUpdateBroadcastResponse, messages.CanvasUpdatePayload{
			DrawPaths: paths,
		})

		return p
	}

	if msg.Type == messages.ClientClearDrawing && gs.isDrawer(player) {
		clear(gs.Canvas.PathStack)

		go gs.Broadcaster.Broadcast(messages.CanvasUpdateBroadcastResponse, messages.CanvasUpdatePayload{
			DrawPaths: make([]messages.DrawEventPayload, 0),
		})
	}

	if msg.Type == messages.ClientFill && gs.isDrawer(player) {
		var fillPayload messages.ClientFillPayload
		if err := json.Unmarshal(msg.Payload, &fillPayload); err != nil {
			player.SendError("invalid fill payload format")
			return p
		}

		gs.Canvas.Actions = append(gs.Canvas.Actions, "fill")

		c := gs.Canvas.FillStack[0]
		startX := int(fillPayload.X)
		startY := int(fillPayload.Y)
		FloodFill(c, startX, startY, fillPayload.Color)

		rasterData := CanvasToPNGDataURL(gs.Canvas.FillStack[0])

		go gs.Broadcaster.Broadcast(messages.RasterUpdateBroadcastResponse, messages.RasterUpdatePayload{
			RasterData: rasterData,
		})

		return p
	}

	return p
}

func (p *RoundInProgressHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	return ackPhaseTransitionTo(&DelayHandler{
		NextPhase:     &RoundScoreDisplayHandler{},
		DelayDuration: 1 * time.Second,
		CurrentPhase:  GamePhaseRoundInProgress,
		DelayMessage:  "Starting 1-second delay before score display (timer expired)",
	})
}

func (gs *GameState) allOtherPlayers(excludePlayer *Player) []*Player {
	playersToSendTo := make([]*Player, 0, len(gs.Players)-1)
	for _, player := range gs.Players {
		if player != nil && player.Id != excludePlayer.Id {
			playersToSendTo = append(playersToSendTo, player)
		}
	}
	return playersToSendTo
}

func (gs *GameState) HandleRasterDrawEvent(drawEvent messages.DrawEventPayload) {
	currentX := int(drawEvent.X)
	currentY := int(drawEvent.Y)

	c := gs.Canvas.FillStack[0]

	switch drawEvent.EventType {
	case "start":
		DrawPathPixel(c, currentX, currentY, int(drawEvent.LineWidth))
		gs.PrevX = currentX
		gs.PrevY = currentY

	case "draw":
		if gs.PrevX != -1 && gs.PrevY != -1 {
			DrawLine(c, gs.PrevX, gs.PrevY, currentX, currentY, int(drawEvent.LineWidth))
		}
		gs.PrevX = currentX
		gs.PrevY = currentY
	}
}
