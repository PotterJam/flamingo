package game

import (
	"log"
	"sort"
	"time"
)

const (
	baseScore                = 300
	subsequentGuesserPenalty = 25
	minGuesserScore          = 50
	maxTimePenalty           = 225
	firstGuessBonus          = 100
)

func calculateGuesserScoreAtTime(
	guessTime time.Time,
	turnDuration time.Duration,
	guesserNumber int,
	firstGuessTime *time.Time,
) int {
	if firstGuessTime == nil {
		return 0
	}

	timeTaken := guessTime.Sub(*firstGuessTime)

	timeRatio := float64(timeTaken) / float64(turnDuration)

	if timeRatio < 0 {
		timeRatio = 0
	} else if timeRatio > 1.0 {
		timeRatio = 1.0
	}

	score := baseScore - int(float64(maxTimePenalty)*timeRatio)

	if guesserNumber == 0 {
		score += firstGuessBonus
	} else {
		score -= subsequentGuesserPenalty * (guesserNumber - 1)
	}

	if score < minGuesserScore {
		return minGuesserScore
	}

	return score
}

type GuessTime struct {
	playerId  string
	guessTime time.Time
}

func calculateRoundScores(gs *GameState) map[string]int {
	roundScores := make(map[string]int)
	if gs.CurrentDrawerIdx < 0 || gs.CurrentDrawerIdx >= len(gs.Players) {
		log.Printf("calculateRoundScores: Invalid drawer index %d, cannot calculate drawer bonus.", gs.CurrentDrawerIdx)
	} else {
		drawer := gs.Players[gs.CurrentDrawerIdx]
		roundScores[drawer.Id] = 0
	}

	numGuessers := len(gs.CorrectGuessTimes)

	guessTimeSlice := make([]GuessTime, 0, len(gs.CorrectGuessTimes))
	for id, t := range gs.CorrectGuessTimes {
		guessTimeSlice = append(guessTimeSlice, GuessTime{
			playerId:  id,
			guessTime: t,
		})
	}

	sort.Slice(guessTimeSlice, func(i, j int) bool {
		return guessTimeSlice[i].guessTime.Before(guessTimeSlice[j].guessTime)
	})

	var firstGuessTime *time.Time = nil
	if numGuessers > 0 {
		firstGuessTime = &guessTimeSlice[0].guessTime
	}

	for i, guess := range guessTimeSlice {
		roundScores[guess.playerId] = calculateGuesserScoreAtTime(guess.guessTime, gs.RoundDuration, i, firstGuessTime)
	}

	if gs.CurrentDrawerIdx >= 0 && gs.CurrentDrawerIdx < len(gs.Players) {
		drawer := gs.Players[gs.CurrentDrawerIdx]
		totalPossibleGuessers := len(gs.Players) - 1 // Everyone except the drawer

		var drawerScore int
		if totalPossibleGuessers == 0 {
			drawerScore = 0
		} else if numGuessers == 0 {
			drawerScore = -100
		} else if numGuessers == 1 {
			drawerScore = 100
		} else {
			// Scale linearly from 100 (one guesser) to 350 (all guessers)
			ratio := float64(numGuessers-1) / float64(totalPossibleGuessers-1)
			drawerScore = 100 + int(ratio*250) // 250 = 350 - 100
		}

		roundScores[drawer.Id] += drawerScore
	}

	return roundScores
}
