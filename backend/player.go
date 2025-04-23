package main

import (
	"encoding/json" // Needed here
	"log"           // Needed here

	"github.com/gorilla/websocket" // Needed here
)

// Player represents a single connected client.
type Player struct {
	ID   string
	Name string // Player's chosen name
	Conn *websocket.Conn
	Hub  *Hub
	Send chan []byte // Buffered channel for outbound messages
}

// readPump pumps messages from the WebSocket connection to the hub.
func (p *Player) readPump() {
	defer func() {
		p.Hub.Unregister <- p
		p.Conn.Close()
		log.Printf("Player %s (%s) disconnected and readPump cleaned up", p.ID, p.Name)
	}()

	hasSetName := false

	for {
		_, messageBytes, err := p.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Player %s (%s) read error: %v", p.ID, p.Name, err)
			} else {
				log.Printf("Player %s (%s) connection closed normally.", p.ID, p.Name)
			}
			break
		}

		var msg Message
		if err := json.Unmarshal(messageBytes, &msg); err != nil {
			log.Printf("Player %s (%s): Error unmarshalling message: %v", p.ID, p.Name, err)
			if !hasSetName {
				p.SendError("Invalid message format. Please set name first.")
			} else {
				p.SendError("Invalid message format")
			}
			continue
		}

		// --- Handle SetName directly in readPump ---
		if msg.Type == MsgTypeSetName {
			if !hasSetName { // Only process if name hasn't been set yet
				var namePayload SetNamePayload
				if err := json.Unmarshal(msg.Payload, &namePayload); err == nil {
					trimmedName := namePayload.Name                  // Trim space later if needed
					if trimmedName != "" && len(trimmedName) <= 20 { // Example length limit
						p.Name = trimmedName // Set the player's name
						hasSetName = true
						log.Printf("Player %s set name to %s", p.ID, p.Name)
						log.Printf("Player %s (%s) sending PlayerReady signal to Hub", p.ID, p.Name)
						p.Hub.PlayerReady <- p // Signal Hub that player is ready
					} else {
						p.SendError("Invalid name. Must be 1-20 characters.")
					}
				} else {
					log.Printf("Player %s (%s): Error unmarshalling SetName payload: %v", p.ID, p.Name, err)
					p.SendError("Invalid name payload.")
				}
			} else {
				// Name already set, ignore subsequent setName messages silently or send error
				log.Printf("Player %s (%s) sent setName message after name was already set. Ignoring.", p.ID, p.Name)
				// Optionally send an error: p.SendError("Name already set.")
			}
		} else if !hasSetName {
			// Ignore other messages until name is set
			log.Printf("Player %s (%s) sent message type %s before setting name.", p.ID, p.Name, msg.Type)
			p.SendError("Please set your name first.")
		} else {
			// Name is set, route other valid messages to the Hub
			p.Hub.HandleMessage(p, msg)
		}
	}
}

// writePump pumps messages from the player's Send channel to the WebSocket connection.
func (p *Player) writePump() {
	defer func() {
		p.Conn.Close()
		log.Printf("Player %s (%s) writePump stopped.", p.ID, p.Name)
	}()

	for {
		select {
		case message, ok := <-p.Send:
			if !ok {
				log.Printf("Player %s (%s): Hub closed send channel.", p.ID, p.Name)
				// Attempt to send close message, ignore error as connection might be dead
				_ = p.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := p.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				log.Printf("Player %s (%s) write error getting writer: %v", p.ID, p.Name, err)
				return
			}
			_, err = w.Write(message)
			if err != nil {
				log.Printf("Player %s (%s) write error writing message: %v", p.ID, p.Name, err)
				_ = w.Close() // Attempt to close writer even on error
				return
			}

			if err := w.Close(); err != nil {
				log.Printf("Player %s (%s) writer close error: %v", p.ID, p.Name, err)
				return
			}
		}
	}
}

// SendError sends a structured error message back to this specific player.
func (p *Player) SendError(errMsg string) {
	// Ensure player pointer is not nil (might happen during rapid disconnect/cleanup)
	if p == nil {
		return
	}
	payload := ErrorPayload{Message: errMsg}
	// Use mustMarshal helper for simplicity, assuming payload struct is always valid
	msgBytes, _ := json.Marshal(Message{Type: MsgTypeError, Payload: json.RawMessage(mustMarshal(payload))})
	// Use a non-blocking send
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Failed to send error message '%s', Send channel likely closed.", p.ID, p.Name, errMsg)
	}
}

// SendMessage sends any message type to this player (non-blocking).
func (p *Player) SendMessage(msgType string, payload interface{}) {
	// Ensure player pointer is not nil
	if p == nil {
		return
	}
	// Use json.RawMessage(nil) for messages without payload
	var payloadBytes []byte
	var err error
	if payload != nil {
		payloadBytes, err = json.Marshal(payload)
		if err != nil {
			log.Printf("Player %s (%s): Error marshalling payload for type %s: %v", p.ID, p.Name, msgType, err)
			return
		}
	}

	msg := Message{Type: msgType, Payload: json.RawMessage(payloadBytes)}
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Player %s (%s): Error marshalling message for type %s: %v", p.ID, p.Name, msgType, err)
		return
	}

	// Use non-blocking send to avoid deadlocks if writePump is stuck or channel closed
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Send channel full/closed for message type %s.", p.ID, p.Name, msgType)
	}
}
