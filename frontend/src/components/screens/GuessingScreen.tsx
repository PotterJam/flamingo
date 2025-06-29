import { Component } from 'solid-js';
import { useAppStore } from '../../store';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../Game';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import WordDisplay from '../WordDisplay';
import TimerDisplay from '../TimerDisplay';
import Whiteboard from '../Whiteboard';
import GuessInput from '../GuessInput';

export const GuessingScreen: Component = () => {
    const store = useAppStore();
    
    const sendMessage = () => store.sendMessage;
    const players = () => store.gameState.players;
    const currentDrawerId = () => store.gameState.currentDrawerId;
    const hostId = () => store.gameState.hostId;
    const localPlayerId = () => store.gameState.localPlayerId;
    const word = () => store.gameState.word;
    const wordOutline = () => store.gameState.wordOutline;
    const turnEndTime = () => store.gameState.turnEndTime;

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
                class="flex flex-col gap-4 lg:flex-row"
                style={{ width: `${250 + CANVAS_WIDTH + 250 + 64}px` }}
            >
                {/* Players Panel */}
                <aside
                    class="flex w-full flex-shrink-0 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]"
                    style={{ "max-height": `${CANVAS_HEIGHT + 100}px` }}
                >
                    <h2 class="flex-shrink-0 border-b pb-2 text-xl font-semibold">
                        Players ({players().length})
                    </h2>
                    <div class="min-h-0 flex-grow overflow-y-auto">
                        <PlayerList
                            players={players()}
                            currentDrawerId={currentDrawerId()}
                            hostId={hostId()}
                        />
                    </div>
                </aside>

                {/* Game Area */}
                <section class="order-2 flex w-full flex-col rounded-lg bg-white p-6 shadow-lg lg:flex-1">
                    <div class="mb-4 flex flex-shrink-0 items-center justify-between gap-4">
                        <div class="min-w-0 flex-1 text-center">
                            {word() && word() !== '' ? (
                                <WordDisplay word={word() ?? ''} />
                            ) : currentDrawerId() ? (
                                <WordDisplay wordOutline={wordOutline() ?? []} />
                            ) : (
                                <div class="h-8 md:h-10"></div>
                            )}
                        </div>
                        <div class="w-20 flex-shrink-0 text-right">
                            {turnEndTime() && (
                                <TimerDisplay endTime={turnEndTime()!} />
                            )}
                        </div>
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
                    class="flex w-full flex-shrink-0 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-3 lg:w-[250px]"
                    style={{ "max-height": `${CANVAS_HEIGHT + 100}px` }}
                >
                    <h2 class="flex-shrink-0 border-b pb-2 text-xl font-semibold">
                        Chat
                    </h2>
                    <div class="min-h-0 flex-grow overflow-y-hidden">
                        <ChatBox />
                    </div>
                    
                    <div class="flex-shrink-0">
                        <GuessInput onGuess={handleGuess} />
                    </div>
                </aside>
            </div>
        </div>
    );
};