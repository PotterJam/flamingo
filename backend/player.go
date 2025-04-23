package main

import (
	"encoding/json"
	"github.com/gorilla/websocket"
	"log"
)

// Player represents a single connected client with a WebSocket connection.
type Player struct {
	ID   string
	Conn *websocket.Conn
	Hub  *Hub        // Reference back to the central hub
	Game *Game       // Reference to the game the player is currently in (nil if none)
	Send chan []byte // Buffered channel for outbound messages to this player
}

// readPump pumps messages from the WebSocket connection to the hub.
// It runs in its own goroutine for each player.
func (p *Player) readPump() {
	defer func() {
		// Cleanup actions when the readPump exits (due to error or connection close)
		p.Hub.Unregister <- p // Signal the hub to unregister this player
		if p.Game != nil {
			// If the player was in a game, notify the game logic
			p.Game.HandleDisconnect(p)
		}
		p.Conn.Close() // Close the WebSocket connection
		log.Printf("Player %s disconnected and cleaned up", p.ID)
	}()
	// Optional: Set connection limits (read limit, deadlines for pong messages)
	// p.Conn.SetReadLimit(maxMessageSize)
	// p.Conn.SetReadDeadline(time.Now().Add(pongWait))
	// p.Conn.SetPongHandler(func(string) error { p.Conn.SetReadDeadline(time.Now().Add(pongWait)); return nil })

	// Loop indefinitely, reading messages from the WebSocket
	for {
		_, messageBytes, err := p.Conn.ReadMessage()
		if err != nil {
			// Check for expected close errors vs unexpected ones
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Player %s read error: %v", p.ID, err)
			} else {
				log.Printf("Player %s connection closed normally.", p.ID)
			}
			break // Exit loop on any error (triggers defer cleanup)
		}

		// Process the received message
		var msg Message
		if err := json.Unmarshal(messageBytes, &msg); err != nil {
			log.Printf("Player %s: Error unmarshalling message: %v", p.ID, err)
			p.SendError("Invalid message format") // Send error back to client
			continue                              // Skip processing this message
		}

		// Route the message to the Hub for handling (which might delegate to the Game)
		p.Hub.HandleMessage(p, msg)
	}
}

// writePump pumps messages from the player's Send channel to the WebSocket connection.
// It runs in its own goroutine for each player.
func (p *Player) writePump() {
	// Optional: Setup a ticker for sending ping messages to keep connection alive
	// ticker := time.NewTicker(pingPeriod)
	defer func() {
		// Cleanup actions when the writePump exits
		// ticker.Stop()
		p.Conn.Close() // Ensure connection is closed if writing fails
		log.Printf("Player %s writePump stopped.", p.ID)
	}()

	// Loop, taking messages from the Send channel and writing them to the WebSocket
	for message := range p.Send {
		// Optional: Set a write deadline
		// p.Conn.SetWriteDeadline(time.Now().Add(writeWait))
		w, err := p.Conn.NextWriter(websocket.TextMessage)
		if err != nil {
			log.Printf("Player %s write error getting writer: %v", p.ID, err)
			return // Exit loop on error
		}
		_, err = w.Write(message)
		if err != nil {
			log.Printf("Player %s write error writing message: %v", p.ID, err)
			// Attempt to close writer even on error
			_ = w.Close()
			return
		}

		// Optional: Add queued chat messages to the current websocket message.
		// n := len(p.Send)
		// for i := 0; i < n; i++ {
		// 	w.Write(newline) // Assuming newline is defined elsewhere
		// 	w.Write(<-p.Send)
		// }

		// Close the writer to flush the message to the connection
		if err := w.Close(); err != nil {
			log.Printf("Player %s writer close error: %v", p.ID, err)
			return // Exit loop on error
		}

		// Optional: Ping handling
		// select {
		// case <-ticker.C:
		// 	p.Conn.SetWriteDeadline(time.Now().Add(writeWait))
		// 	if err := p.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
		// 		return
		// 	}
		// default:
		// }
	}
	// If the loop exits, it means the p.Send channel was closed (likely during unregistration)
}

// SendError is a helper method to send a structured error message back to this specific player.
func (p *Player) SendError(errMsg string) {
	payload := ErrorPayload{Message: errMsg}
	// Use mustMarshal helper for simplicity, assuming payload struct is always valid
	msgBytes, _ := json.Marshal(Message{Type: MsgTypeError, Payload: json.RawMessage(mustMarshal(payload))})

	// Use a non-blocking send to avoid deadlocking if the send channel is full or closed
	select {
	case p.Send <- msgBytes:
		// Message sent successfully
	default:
		// Channel likely closed or full, log it
		log.Printf("Player %s: Failed to send error message '%s', Send channel likely closed.", p.ID, errMsg)
	}
}
