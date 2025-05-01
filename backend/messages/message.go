package messages

import (
	"encoding/json"
	"log"
)

type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

func MustMarshal(v any) []byte {
	bytes, err := json.Marshal(v)
	if err != nil {
		log.Panicf("Failed to marshal known valid structure: %v", err)
	}
	return bytes
}
