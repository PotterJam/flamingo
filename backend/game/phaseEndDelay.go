package game

import (
	"backend/messages"
	"log"
	"time"
)

type DelayHandler struct {
	NextPhase     GamePhaseHandler
	DelayDuration time.Duration
	CurrentPhase  GamePhase // What phase to report during delay
	DelayMessage  string    // Log message to show when starting delay
}

func (p *DelayHandler) Phase() GamePhase {
	return p.CurrentPhase
}

func (p *DelayHandler) StartPhase(gs *GameState) {
	// Add configurable delay before transitioning to next phase
	gs.timerForTimeout = time.NewTimer(p.DelayDuration)
	gs.turnEndTime = time.Now().Add(p.DelayDuration)

	if p.DelayMessage != "" {
		log.Println("GameState:", p.DelayMessage)
	} else {
		log.Printf("GameState: Starting %v delay before next phase", p.DelayDuration)
	}
}

func (p *DelayHandler) HandleMessage(gs *GameState, player *Player, msg messages.Message) GamePhaseHandler {
	// Ignore all messages during the delay
	return p
}

func (p *DelayHandler) HandleTimeOut(gs *GameState) GamePhaseHandler {
	log.Printf("GameState: Delay finished (%v), transitioning to next phase", p.DelayDuration)
	return ackPhaseTransitionTo(p.NextPhase)
}
