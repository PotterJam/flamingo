package main

import (
	"encoding/json"
	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"log"
	"net/http"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		log.Printf("WebSocket CheckOrigin request from: %s", r.Header.Get("Origin"))
		return true // Allow all for dev
	},
}

var words = []string{"apple", "banana", "cloud", "house", "tree", "computer", "go", "svelte", "network", "game", "player", "draw", "timer", "guess", "score", "host", "lobby", "react"}

func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
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
		Hub:  hub,
		Send: make(chan []byte, 256),
	}

	log.Printf("Registering new player connection: %s", player.ID)
	hub.Register <- player

	go player.writePump()
	go player.readPump()
}

func main() {
	hub := NewHub()
	go hub.Run()

	router := mux.NewRouter()
	router.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(hub, w, r)
	})

	// Static File Serving
	staticDir := "./public" // Assumes React build is copied here
	fileServer := http.FileServer(http.Dir(staticDir))
	router.PathPrefix("/assets/").Handler(fileServer) // Vite typically uses /assets/
	router.PathPrefix("/").HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		filePath := staticDir + r.URL.Path
		if _, err := http.Dir(staticDir).Open(r.URL.Path); err != nil {
			log.Printf("Serving index.html for path: %s", r.URL.Path)
			http.ServeFile(w, r, staticDir+"/index.html") // Serve index for client routing
			return
		}
		log.Printf("Serving static file: %s", filePath)
		fileServer.ServeHTTP(w, r) // Serve existing static file
	})

	port := "8080"
	log.Printf("Server starting on http://localhost:%s", port)
	server := &http.Server{Addr: ":" + port, Handler: router}
	err := server.ListenAndServe()
	if err != nil {
		log.Fatal("ListenAndServe Error: ", err)
	}
}

// mustMarshal will panic on error.
// Useful for internal message creation where the structure is known to be valid.
// Use with caution for external or user-provided data.
func mustMarshal(v interface{}) []byte {
	bytes, err := json.Marshal(v)
	if err != nil {
		// Panic is acceptable here if we are sure the input `v` is always marshallable.
		// If not, return an error instead.
		log.Panicf("Failed to marshal known valid structure: %v", err)
	}
	return bytes
}
