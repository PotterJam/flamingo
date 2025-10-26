package game

import (
	"log"
	"sort"
	"time"
)

const (
	baseScore                      = 300
	subsequentGuesserMinDifference = 25
	minGuesserScore                = 50
	maxTimePenalty                 = 250
	firstGuessBonus                = 100
)

type GuesserScore struct {
	PlayerId string
	Score    int
}

func calculateGuesserScores(correctGuessTimes map[string]time.Time, turnDuration time.Duration) []GuesserScore {
	numGuessers := len(correctGuessTimes)

	guessTimeSlice := make([]GuessTime, 0, len(correctGuessTimes))
	for id, t := range correctGuessTimes {
		guessTimeSlice = append(guessTimeSlice, GuessTime{
			playerId: id,
			Time:     t,
		})
	}

	sort.Slice(guessTimeSlice, func(i, j int) bool {
		return guessTimeSlice[i].Time.Before(guessTimeSlice[j].Time)
	})

	var firstGuessTime *time.Time = nil
	if numGuessers > 0 {
		firstGuessTime = &guessTimeSlice[0].Time
	}

	guesserScores := make([]GuesserScore, 0, numGuessers)

	if firstGuessTime == nil {
		return guesserScores
	}

	for guessNumber, guess := range guessTimeSlice {

		timeTaken := guess.Time.Sub(*firstGuessTime)

		timeRatio := float64(timeTaken) / float64(turnDuration)

		if timeRatio < 0 {
			timeRatio = 0
		} else if timeRatio > 1.0 {
			timeRatio = 1.0
		}

		score := baseScore - int(float64(maxTimePenalty)*timeRatio)

		if guessNumber == 0 {
			score += firstGuessBonus
		} else {
			previousGuesserScore := guesserScores[guessNumber-1]
			if (previousGuesserScore.Score - score) < subsequentGuesserMinDifference {
				score = previousGuesserScore.Score - subsequentGuesserMinDifference
			}
		}

		if score < minGuesserScore {
			score = minGuesserScore
		}

		guesserScores = append(guesserScores, GuesserScore{guess.playerId, score})
	}

	return guesserScores
}

type GuessTime struct {
	playerId string
	Time     time.Time
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

	guesserScores := calculateGuesserScores(gs.CorrectGuessTimes, gs.RoundDuration)

	for _, guess := range guesserScores {
		roundScores[guess.PlayerId] = guess.Score
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
