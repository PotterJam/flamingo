package main

import (
	"encoding/json"
	"log"
)

func MustMarshal(v any) []byte {
	bytes, err := json.Marshal(v)
	if err != nil {
		log.Panicf("Failed to marshal known valid structure: %v", err)
	}
	return bytes
}

// Name can be nil if not set yet but that breaks all our logging, this is basically a null coalesce to "Unnamed"
func LogName(namePtr *string) string {
	if namePtr != nil {
		return *namePtr
	} else {
		return "Unnamed"
	}
}
