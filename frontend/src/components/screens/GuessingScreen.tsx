import { Component } from 'solid-js';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../Game';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import Whiteboard from '../Whiteboard';
import GuessInput from '../GuessInput';
import { store } from '../../store';
import { GameHeader } from '../GameHeader';

export const GuessingScreen: Component = () => {
    const sendMessage = () => store.sendMessage;
    const players = () => store.gameState.players;
    const currentDrawerId = () => store.gameState.currentDrawerId;
    const localPlayerId = () => store.gameState.localPlayerId;

    const localPlayer = () => players().find((p) => p.id === localPlayerId());
    const isLocalPlayerDrawer = () => localPlayerId() === currentDrawerId();

    const handleGuess = (message: string) => {
        if (isLocalPlayerDrawer() || localPlayer()?.hasGuessedCorrectly) {
            sendMessage()({ type: 'chat', payload: { message: message } });
        } else {
            sendMessage()({ type: 'guess', payload: { guess: message } });
        }
    };

    return (
        <div class="flex w-full flex-grow justify-center">
            <div
                class="flex flex-col gap-2 lg:flex-row"
                style={{ width: `${250 + CANVAS_WIDTH + 250 + 64}px` }}
            >
                <aside
                    class="flex w-full flex-shrink-0 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]"
                    style={{ 'max-height': `${CANVAS_HEIGHT + 100}px` }}
                >
                    <h2 class="flex-shrink-0 border-b pb-2 text-xl font-semibold">
                        Players ({players().length})
                    </h2>
                    <div class="min-h-0 flex-grow overflow-y-auto">
                        <PlayerList />
                    </div>
                </aside>

                {/* Game Area */}
                <section class="pixel-purple order-2 flex flex-col border-4 border-blue-300 border-t-blue-200 border-l-blue-200 p-6">
                    <div class="mb-4 flex items-center justify-between gap-4">
                        <GameHeader />
                    </div>
                    <div class="relative overflow-hidden bg-white">
                        <Whiteboard
                            width={CANVAS_WIDTH}
                            height={CANVAS_HEIGHT}
                        />
                    </div>
                </section>

                {/* Chat Panel */}
                <aside
                    class="pixel-gray my-auto flex h-4/5 w-full flex-shrink-0 flex-col gap-4 border-4 border-gray-500 border-t-gray-300 border-l-gray-300 p-4 shadow-lg lg:order-3 lg:w-[250px]"
                    style={{ 'max-height': `${CANVAS_HEIGHT + 100}px` }}
                >
                    <div class="min-h-0 flex-grow overflow-y-hidden">
                        <ChatBox />
                    </div>

                    <div class="flex-shrink-0 bg-white">
                        <GuessInput onGuess={handleGuess} />
                    </div>
                </aside>
            </div>
        </div>
    );
};
