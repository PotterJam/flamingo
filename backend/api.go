package main

import (
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		log.Printf("WebSocket CheckOrigin request from: %s", r.Header.Get("Origin"))
		return true // TODO: needs to be localhost or the registered domain
	},
}

func ServeWS(rm *RoomManager, w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	roomId, ok := vars["roomId"]
	if !ok {
		log.Println("no room id provided")
		w.WriteHeader(http.StatusNotFound)
		return
	}

	room := rm.GetRoom(roomId)
	if room == nil {
		log.Printf("room %s not found", roomId)
		w.WriteHeader(http.StatusNotFound)
		return
	}

	playerName := r.URL.Query().Get("playerName")
	if playerName == "" {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	log.Println("Client connected via WebSocket from:", conn.RemoteAddr())

	player := &Player{
		Id:   uuid.NewString(),
		Name: playerName,
		Conn: conn,
		Room: room,
		Send: make(chan []byte, 256),
	}

	log.Printf("Registering new player connection to room %s: %s", roomId, player.Id)
	room.Register <- player
	room.PlayerReady <- player

	go player.writePump()
	go player.readPump()
	go room.Game.HandleEvents()
}
