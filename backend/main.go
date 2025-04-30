package main

import (
	"log"
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	rm := NewRoomManager()
	go rm.Run()

	staticDir := "./public"
	fileServer := http.FileServer(http.Dir(staticDir))

	router := mux.NewRouter()

	router.HandleFunc("/ws/{roomId}", func(w http.ResponseWriter, r *http.Request) { ServeWS(rm, w, r) })
	router.PathPrefix("/assets/").Handler(fileServer)
	router.Path("/").HandlerFunc(func(w http.ResponseWriter, r *http.Request) { HandleIndex(staticDir, fileServer, w, r) })
	router.PathPrefix("/create-room").Methods(http.MethodPost).HandlerFunc(func(w http.ResponseWriter, r *http.Request) { HandleCreateRoom(rm, w, r) })
	router.PathPrefix("/{roomId}").Methods(http.MethodGet).HandlerFunc(func(w http.ResponseWriter, r *http.Request) { HandleGetRoom(rm, w, r) })

	port := "8080"
	log.Printf("Server starting on http://localhost:%s", port)
	server := &http.Server{Addr: ":" + port, Handler: router}
	err := server.ListenAndServe()
	if err != nil {
		log.Fatal("ListenAndServe Error: ", err)
	}
}
