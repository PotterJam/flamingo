package main

import (
	"encoding/json"
	"github.com/gorilla/websocket"
	"log"
)

// Player represents a single connected client.
type Player struct {
	ID   string
	Name *string // Player's chosen name
	Conn *websocket.Conn
	Room *Room
	Send chan []byte // Buffered channel for outbound messages
}

// readPump pumps messages from the WebSocket connection to the hub.
func (p *Player) readPump() {
	defer func() {
		p.Room.Unregister <- p
		_ = p.Conn.Close()

		log.Printf("Player %s (%s) disconnected and readPump cleaned up", p.ID, LogName(p.Name))
	}()

	for {
		_, messageBytes, err := p.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Player %s (%s) read error: %v", p.ID, LogName(p.Name), err)
			} else {
				log.Printf("Player %s (%s) connection closed normally.", p.ID, LogName(p.Name))
			}
			break
		}

		var msg Message
		if err := json.Unmarshal(messageBytes, &msg); err != nil {
			log.Printf("Player %s (%s): Error unmarshalling message: %v", p.ID, *p.Name, err)
			p.SendError("Invalid message format")
			continue
		}

		p.Room.HandleMessage(p, msg)
	}
}

// writePump pumps messages from the player's Send channel to the WebSocket connection.
func (p *Player) writePump() {
	defer func() {
		p.Conn.Close()
		log.Printf("Player %s (%s) writePump stopped.", p.ID, LogName(p.Name))
	}()

	for {
		select {
		case message, ok := <-p.Send:
			if !ok {
				log.Printf("Player %s (%s): Room closed send channel.", p.ID, LogName(p.Name))
				_ = p.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := p.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				log.Printf("Player %s (%s) write error getting writer: %v", p.ID, LogName(p.Name), err)
				return
			}
			_, err = w.Write(message)
			if err != nil {
				log.Printf("Player %s (%s) write error writing message: %v", p.ID, LogName(p.Name), err)
				_ = w.Close()
				return
			}

			if err := w.Close(); err != nil {
				log.Printf("Player %s (%s) writer close error: %v", p.ID, LogName(p.Name), err)
				return
			}
		}
	}
}

func (p *Player) SendError(errMsg string) {
	if p == nil {
		return
	}
	payload := ErrorPayload{Message: errMsg}

	msgBytes, _ := json.Marshal(Message{Type: TypeErrorResponse, Payload: json.RawMessage(MustMarshal(payload))})
	// Use a non-blocking send
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Failed to send error message '%s', Send channel likely closed.", p.ID, *p.Name, errMsg)
	}
}

// SendMessage sends any message type to this player (non-blocking).
func (p *Player) SendMessage(msgType string, payload any) {
	if p == nil {
		return
	}

	var payloadBytes []byte
	var err error
	if payload != nil {
		payloadBytes, err = json.Marshal(payload)
		if err != nil {
			log.Printf("Player %s (%s): Error marshalling payload for type %s: %v", p.ID, *p.Name, msgType, err)
			return
		}
	}

	msg := Message{Type: msgType, Payload: json.RawMessage(payloadBytes)}
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Player %s (%s): Error marshalling message for type %s: %v", p.ID, *p.Name, msgType, err)
		return
	}

	// Use non-blocking send to avoid deadlocks if writePump is stuck or channel closed
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Send channel full/closed for message type %s.", p.ID, *p.Name, msgType)
	}
}
