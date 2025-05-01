package game

import (
	"log"
	"time"
)

const (
	baseScore          = 300
	maxTimePenalty     = 225
	firstGuessBonus    = 100
	drawerPartialBonus = 50
	drawerFullBonus    = 100
)

func calculateGuesserScoreAtTime(turnStartTime, guessTime time.Time, turnDuration time.Duration, isFirstGuesser bool) int {
	timeTaken := guessTime.Sub(turnStartTime)

	timeRatio := float64(timeTaken) / float64(turnDuration)

	if timeRatio < 0 {
		timeRatio = 0
	} else if timeRatio > 1.0 {
		timeRatio = 1.0
	}

	score := baseScore - int(float64(maxTimePenalty)*timeRatio)

	if isFirstGuesser {
		score += firstGuessBonus
	}
	return score
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
	allGuessed := gs.checkAllGuessed()
	firstGuesserID := ""
	earliestGuessTime := time.Time{}

	for playerID, guessTime := range gs.CorrectGuessTimes {
		if earliestGuessTime.IsZero() || guessTime.Before(earliestGuessTime) {
			earliestGuessTime = guessTime
			firstGuesserID = playerID
		}
	}

	for playerID, guessTime := range gs.CorrectGuessTimes {
		isFirst := playerID == firstGuesserID
		roundScores[playerID] = calculateGuesserScoreAtTime(gs.TurnStartTime, guessTime, turnDuration, isFirst)
	}

	if numGuessers > 0 && gs.CurrentDrawerIdx >= 0 && gs.CurrentDrawerIdx < len(gs.Players) {
		drawer := gs.Players[gs.CurrentDrawerIdx]
		if allGuessed {
			roundScores[drawer.Id] += drawerFullBonus
		} else {
			roundScores[drawer.Id] += drawerPartialBonus
		}
	}

	return roundScores
}
