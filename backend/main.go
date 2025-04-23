package main

import (
	"encoding/json"
	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"log"
	"math/rand"
	"net/http"
	"time"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true }, // Allow all origins for dev
}

// serveWs handles WebSocket upgrade requests from clients.
func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
	// Upgrade the HTTP connection to a WebSocket connection
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	log.Println("Client connected via WebSocket from:", conn.RemoteAddr())

	// Create a new Player instance for this connection
	player := &Player{
		ID:   uuid.NewString(), // Assign a unique ID to the player
		Conn: conn,
		Hub:  hub,
		Send: make(chan []byte, 256), // Create a buffered channel for outgoing messages
		Game: nil,                    // Initially not in any game
	}

	// Register the new player with the hub
	player.Hub.Register <- player

	// Start the readPump and writePump goroutines for this player
	// These handle communication for this specific connection.
	go player.writePump()
	go player.readPump() // readPump handles unregistration on disconnect/error
}

// main is the application entry point.
func main() {
	// Seed the random number generator (important for word selection/role assignment)
	rand.Seed(time.Now().UnixNano())

	// Create and run the central Hub in its own goroutine
	hub := NewHub()
	go hub.Run()

	// Create a new router (using gorilla/mux here)
	router := mux.NewRouter()

	// WebSocket endpoint handler
	router.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(hub, w, r)
	})

	// --- Static File Serving for Svelte Frontend ---
	// Define the directory containing the built Svelte app
	// IMPORTANT: Adjust "./public" if your Go executable runs from a different
	// location relative to the 'public' folder.
	staticDir := "./public"
	// Create a file server handler
	fs := http.FileServer(http.Dir(staticDir))

	// Serve static files (CSS, JS, images) from the /assets path (or however Vite structures it)
	// Adjust the path prefix based on your Svelte build output structure
	router.PathPrefix("/assets/").Handler(fs)

	// Serve the main index.html for the root path and potentially other routes
	// This ensures that navigating directly to paths handled by Svelte's router works.
	router.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, staticDir+"/index.html")
	})
	// Add more HandleFunc calls here if Svelte uses client-side routing for other paths,
	// all pointing to index.html. Example:
	// router.HandleFunc("/about", func(w http.ResponseWriter, r *http.Request) {
	//     http.ServeFile(w, r, staticDir+"/index.html")
	// })

	// Define the server port
	port := "8080"
	log.Printf("Server starting on http://localhost:%s", port)

	// Start the HTTP server
	err := http.ListenAndServe(":"+port, router)
	if err != nil {
		log.Fatal("ListenAndServe Error: ", err)
	}
}

// =====================================================
// File: utils.go (or keep in main.go if small)
// Purpose: Utility functions used across the application.
// =====================================================

// mustMarshal is a helper to marshal JSON, panicking on error.
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
