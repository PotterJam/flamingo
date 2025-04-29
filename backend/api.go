package main

import (
	"encoding/json"
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
}

type CreateRoomResponse struct {
	RoomId string `json:"roomId"`
}

func HandleCreateRoom(rm *RoomManager, w http.ResponseWriter, r *http.Request) {
	room := rm.CreateRoom()

	res := CreateRoomResponse{
		RoomId: room.Id,
	}

	w.WriteHeader(http.StatusOK)
	err := json.NewEncoder(w).Encode(res)
	if err != nil {
		log.Printf("failed to respond to room creation: %s", err.Error())
	}
}

func HandleGetRoom(rm *RoomManager, w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	roomId, ok := vars["roomId"]
	if !ok {
		log.Println("no room id provided for get room")
		w.WriteHeader(http.StatusNotFound)
		return
	}

	room := rm.GetRoom(roomId)
	if room == nil {
		log.Printf("no room found %s", roomId)
		w.WriteHeader(http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	return
}

func HandleIndex(staticDir string, fs http.Handler, w http.ResponseWriter, r *http.Request) {
	filePath := staticDir + r.URL.Path
	if _, err := http.Dir(staticDir).Open(r.URL.Path); err != nil {
		log.Printf("Serving index.html for path: %s", r.URL.Path)
		http.ServeFile(w, r, staticDir+"/index.html")
		return
	}
	log.Printf("Serving static file: %s", filePath)
	fs.ServeHTTP(w, r)
}
