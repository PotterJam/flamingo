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

var words = []string{"apple", "banana", "cloud", "house", "tree", "computer", "go", "svelte", "network", "game", "player", "draw", "timer", "guess", "score", "host", "lobby", "react"}

func serveWs(room *Room, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	log.Println("Client connected via WebSocket from:", conn.RemoteAddr())

	player := &Player{
		ID:   uuid.NewString(),
		Name: nil, // Name set by player
		Conn: conn,
		Room: room,
		Send: make(chan []byte, 256),
	}

	log.Printf("Registering new player connection: %s", player.ID)
	room.Register <- player

	go player.writePump()
	go player.readPump()
}

type CreateRoomResponse struct {
	RoomId   string `json:"roomId"`
	RoomSlug string `json:"roomSlug"`
}

func main() {
	rm := NewRoomManager()
	go rm.Run()

	room := NewRoom()
	go room.Run()

	router := mux.NewRouter()
	router.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(room, w, r)
	})

	staticDir := "./public"
	fileServer := http.FileServer(http.Dir(staticDir))

	router.PathPrefix("/assets/").Handler(fileServer)

	router.Path("/").HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		filePath := staticDir + r.URL.Path
		if _, err := http.Dir(staticDir).Open(r.URL.Path); err != nil {
			log.Printf("Serving index.html for path: %s", r.URL.Path)
			http.ServeFile(w, r, staticDir+"/index.html")
			return
		}
		log.Printf("Serving static file: %s", filePath)
		fileServer.ServeHTTP(w, r)
	})

	router.PathPrefix("/create-room").Methods(http.MethodPost).HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		room := rm.CreateRoom()
		log.Printf("created new room [%s] %s", room.Id, room.Slug)

		res := CreateRoomResponse{
			RoomId:   room.Id,
			RoomSlug: room.Slug,
		}

		w.WriteHeader(http.StatusOK)
		err := json.NewEncoder(w).Encode(res)
		if err != nil {
			log.Printf("failed to respond to room creation: %e", err.Error())
		}
	})

	port := "8080"
	log.Printf("Server starting on http://localhost:%s", port)
	server := &http.Server{Addr: ":" + port, Handler: router}
	err := server.ListenAndServe()
	if err != nil {
		log.Fatal("ListenAndServe Error: ", err)
	}
}
