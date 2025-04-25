package main

func MustMarshal(v any) []byte {
	bytes, err := json.Marshal(v)
	if err != nil {
		log.Panicf("Failed to marshal known valid structure: %v", err)
	}
	return bytes
}
