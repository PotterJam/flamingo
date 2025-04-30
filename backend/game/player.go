package game

import (
	"backend/messages"
	"encoding/json"
	"log"

	"github.com/gorilla/websocket"
)

// Player represents a single connected client.
type Player struct {
	Id         string
	Name       string
	Score      int
	Conn       *websocket.Conn
	Room       *room.Room
	Unregister chan *Player
	Send       chan []byte // Buffered channel for outbound messages
}

// readPump pumps messages from the WebSocket connection to the hub.
func (p *Player) readPump() {
	defer func() {
		p.Room.Unregister <- p
		_ = p.Conn.Close()

		log.Printf("Player %s (%s) disconnected and readPump cleaned up", p.Id, p.Name)
	}()

	for {
		_, messageBytes, err := p.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Player %s (%s) read error: %v", p.Id, p.Name, err)
			} else {
				log.Printf("Player %s (%s) connection closed normally.", p.Id, p.Name)
			}
			break
		}

		var msg messages.Message
		if err := json.Unmarshal(messageBytes, &msg); err != nil {
			log.Printf("Player %s (%s): Error unmarshalling message: %v", p.Id, p.Name, err)
			p.SendError("Invalid message format")
			continue
		}

		p.Room.Game.Messages <- GameMessage{p, msg}
	}
}

// writePump pumps messages from the player's Send channel to the WebSocket connection.
func (p *Player) writePump() {
	defer func() {
		p.Conn.Close()
		log.Printf("Player %s (%s) writePump stopped.", p.Id, p.Name)
	}()

	for {
		select {
		case message, ok := <-p.Send:
			if !ok {
				log.Printf("Player %s (%s): Room closed send channel.", p.Id, p.Name)
				_ = p.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := p.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				log.Printf("Player %s (%s) write error getting writer: %v", p.Id, p.Name, err)
				return
			}
			_, err = w.Write(message)
			if err != nil {
				log.Printf("Player %s (%s) write error writing message: %v", p.Id, p.Name, err)
				_ = w.Close()
				return
			}

			if err := w.Close(); err != nil {
				log.Printf("Player %s (%s) writer close error: %v", p.Id, p.Name, err)
				return
			}
		}
	}
}

func (p *Player) SendError(errMsg string) {
	if p == nil {
		return
	}
	payload := messages.ErrorPayload{Message: errMsg}

	msgBytes, _ := json.Marshal(messages.Message{Type: messages.TypeErrorResponse, Payload: json.RawMessage(messages.MustMarshal(payload))})
	// Use a non-blocking send
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Failed to send error message '%s', Send channel likely closed.", p.Id, p.Name, errMsg)
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
			log.Printf("Player %s (%s): Error marshalling payload for type %s: %v", p.Id, p.Name, msgType, err)
			return
		}
	}

	msg := messages.Message{Type: msgType, Payload: json.RawMessage(payloadBytes)}
	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Player %s (%s): Error marshalling message for type %s: %v", p.Id, p.Name, msgType, err)
		return
	}

	// Use non-blocking send to avoid deadlocks if writePump is stuck or channel closed
	select {
	case p.Send <- msgBytes:
	default:
		log.Printf("Player %s (%s): Send channel full/closed for message type %s.", p.Id, p.Name, msgType)
	}
}
