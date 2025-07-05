package words

import (
	_ "embed"
	"strings"
)

//go:embed default.txt
var defaultWordList string

var DefaultWords []string

func init() {
	lines := strings.Split(strings.TrimSpace(defaultWordList), "\n")
	DefaultWords = make([]string, 0, len(lines))

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			DefaultWords = append(DefaultWords, line)
		}
	}
}
