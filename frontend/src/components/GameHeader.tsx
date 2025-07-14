import { Component } from 'solid-js/types/server/rendering.js';
import { store } from '../store';
import WordDisplay from './WordDisplay';
import TimerDisplay from './TimerDisplay';

export const GameHeader: Component = () => {
    const word = () => store.gameState.word;
    const wordOutline = () => store.gameState.wordOutline;
    const turnEndTime = () => store.gameState.turnEndTime;

    return (
        <div class="scanlines-light flex w-full flex-row items-center justify-center gap-4 border-4 border-gray-500 border-t-gray-300 border-l-gray-300 bg-black p-4">
            <div class="font-retro translate-y-0.75 text-center text-xl text-amber-400">
                Rd {(store.gameState.currentRound ?? 1) + 1}/
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
