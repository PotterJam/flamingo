package main

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/mux"
)

var words = []string{"apple", "banana", "cloud", "house", "tree", "computer", "go", "svelte", "network", "game", "player", "draw", "timer", "guess", "score", "host", "lobby", "react"}

type CreateRoomResponse struct {
	RoomId string `json:"roomId"`
}

func main() {
	rm := NewRoomManager()
	go rm.Run()

	router := mux.NewRouter()
	router.HandleFunc("/ws/{roomId}", func(w http.ResponseWriter, r *http.Request) {
		ServeWS(rm, w, r)
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
		log.Printf("created new room %s", room.Id)

		res := CreateRoomResponse{
			RoomId: room.Id,
		}

		w.WriteHeader(http.StatusOK)
		err := json.NewEncoder(w).Encode(res)
		if err != nil {
			log.Printf("failed to respond to room creation: %s", err.Error())
		}
	})

	router.PathPrefix("/{roomId}").Methods(http.MethodGet).HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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
	})

	port := "8080"
	log.Printf("Server starting on http://localhost:%s", port)
	server := &http.Server{Addr: ":" + port, Handler: router}
	err := server.ListenAndServe()
	if err != nil {
		log.Fatal("ListenAndServe Error: ", err)
	}
}
