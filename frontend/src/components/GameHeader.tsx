import { Component } from 'solid-js/types/server/rendering.js';
import { store } from '../store';
import WordDisplay from './WordDisplay';
import TimerDisplay from './TimerDisplay';

export const GameHeader: Component = () => {
    const word = () => store.gameState.word;
    const wordOutline = () => store.gameState.wordOutline;
    const turnEndTime = () => store.gameState.turnEndTime;

    return (
        <div>
            <div class="text-center text-gray-600">
                Round {(store.gameState.currentRound ?? 1) + 1} of{' '}
                {store.gameState.totalRounds}
            </div>
            <div class="min-w-0 flex-1 text-center">
                {word() && word() !== '' ? (
                    <WordDisplay word={word() ?? ''} />
                ) : store.gameState.currentDrawerId ? (
                    <WordDisplay wordOutline={wordOutline() ?? []} />
                ) : (
                    <div class="h-8 md:h-10"></div>
                )}
            </div>
            <div class="w-20 flex-shrink-0 text-right">
                {turnEndTime() && <TimerDisplay endTime={turnEndTime()!} />}
            </div>
        </div>
    );
};
