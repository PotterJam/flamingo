import { Component } from 'solid-js/types/server/rendering.js';
import { store } from '../store';
import WordDisplay from './WordDisplay';
import TimerDisplay from './TimerDisplay';

export const GameHeader: Component = () => {
    const turnEndTime = () => store.gameState.turnEndTime;

    return (
        <div class="flex h-12 w-full flex-row items-center justify-between gap-4">
            <p class="flex-1 text-xl font-bold text-white">
                Round {(store.gameState.currentRound ?? 1) + 1} of{' '}
                {store.gameState.totalRounds}
            </p>
            <div class="flex-1">
                <WordDisplay />
            </div>
            <div class="flex-1 text-right">
                {turnEndTime() && <TimerDisplay endTime={turnEndTime()!} />}
            </div>
        </div>
    );
};
