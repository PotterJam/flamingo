package phase

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
