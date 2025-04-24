import { FC, useCallback } from "react";
import { useAppStore } from "../App";
import PlayerList from "./PlayerList";
import ChatBox from "./ChatBox";
import WordDisplay from "./WordDisplay";
import TimerDisplay from "./TimerDisplay";
import Whiteboard from "./Whiteboard";
import GuessInput from "./GuessInput";
import { useWebSocket } from "../hooks/useWebSocket";

const CANVAS_WIDTH = 800;
const CANVAS_HEIGHT = 600;
const MIN_PLAYERS = 2;

export const Game: FC = () => {
    const { lastMessage, sendMessage } = useWebSocket();

    const appState = useAppStore(s => s.appState);
    const gameState = useAppStore(s => s.gameState);
    if (gameState === null) {
        return <div>sad</div>;
    }
    const { players, currentDrawerId, hostId, localPlayerId, word, messages, turnEndTime } = gameState;

    if (!players || !currentDrawerId || !hostId || !localPlayerId || !word || !turnEndTime) {
        throw new Error('game might not be configued properly');
    }

    const localPlayer = players.find(p => p.id === localPlayerId);
    if (!localPlayer) {
        throw new Error('no local player found');
    }
    const isHost = localPlayerId === hostId;
    const isLocalPlayerDrawer = localPlayerId === currentDrawerId;
    const canHostStartGame = isHost && appState === 'waiting' && players.length >= MIN_PLAYERS;

    const canLocalPlayerGuess = !isLocalPlayerDrawer && !localPlayer.hasGuessedCorrectly;

    const wordBlanks = Array(word.length).fill('_').join(' ');

    const handleStartGame = useCallback(() => {
        console.log("Start Game button clicked by host.");
        if (canHostStartGame) {
            sendMessage('startGame', null);
        } else {
            console.warn("Start game attempted but conditions not met.");
        }
    }, [canHostStartGame, sendMessage]);

    const handleDraw = useCallback((drawData: any) => {
        if (isLocalPlayerDrawer && appState === 'active') {
            sendMessage('drawEvent', drawData);
        }
    }, [isLocalPlayerDrawer, appState, sendMessage]);

    const handleGuess = useCallback((guess: string) => {
        if (canLocalPlayerGuess) {
            sendMessage('guess', { guess: guess });
        }
    }, [canLocalPlayerGuess, sendMessage]);

    return (
        <div className="flex justify-center w-full flex-grow">
            <div className="flex flex-col lg:flex-row gap-4"
                style={{ width: `${250 + CANVAS_WIDTH + 32}px` }}>
                <aside
                    className="w-full lg:w-[250px] bg-white shadow-lg rounded-lg p-4 flex flex-col gap-4 order-2 lg:order-1 flex-shrink-0"
                    style={{ maxHeight: `${CANVAS_HEIGHT + 100}px` }}>
                    <h2 className="text-xl font-semibold border-b pb-2 flex-shrink-0">Players
                        ({players.length})</h2>
                    <div className="flex-shrink overflow-y-auto mb-4 min-h-0">
                        <PlayerList players={players} currentDrawerId={currentDrawerId}
                            hostId={hostId} />
                    </div>

                    {canHostStartGame && (
                        <button
                            onClick={handleStartGame}
                            className="px-4 py-2 bg-green-500 text-black font-semibold rounded hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-1 transition duration-150 ease-in-out flex-shrink-0"
                        >
                            Start Game
                        </button>
                    )}

                    <h2 className={`text-xl font-semibold border-b pb-2 flex-shrink-0 ${!canHostStartGame ? 'mt-auto' : ''}`}>Chat</h2>
                    <div className="flex-grow overflow-y-hidden min-h-0">
                        <ChatBox messages={messages} />
                    </div>
                </aside>

                <section
                    className="w-full lg:flex-1 bg-white shadow-lg rounded-lg p-6 flex flex-col order-1 lg:order-2">
                    <div className="flex justify-between items-center mb-4 gap-4 flex-shrink-0">
                        <div className="flex-1 text-center min-w-0">
                            {(isLocalPlayerDrawer) ? (
                                <WordDisplay word={word} />
                            ) : (appState === 'active' && currentDrawerId) ? (
                                <WordDisplay blanks={wordBlanks} length={word.length} />
                            ) : (
                                <div className="h-8 md:h-10"></div>
                            )}
                        </div>
                        <div className="w-20 text-right flex-shrink-0">
                            {(appState === 'active' && turnEndTime) && (
                                <TimerDisplay endTime={turnEndTime} />
                            )}
                        </div>
                    </div>
                    <div
                        className="mb-4 border-2 border-black rounded overflow-hidden bg-white relative"
                        style={{
                            width: `${CANVAS_WIDTH}px`,
                            height: `${CANVAS_HEIGHT}px`
                        }}
                    >
                        <Whiteboard
                            isDrawer={!!isLocalPlayerDrawer}
                            onDraw={handleDraw}
                            lastDrawEvent={lastMessage?.type === 'drawEvent' ? lastMessage.payload : null}
                            localPlayerIsDrawer={!!isLocalPlayerDrawer}
                            width={CANVAS_WIDTH}
                            height={CANVAS_HEIGHT}
                        />
                    </div>

                    {canLocalPlayerGuess && (
                        <div className="flex-shrink-0">
                            <GuessInput onGuess={handleGuess} />
                        </div>
                    )}
                </section>
            </div>
        </div >
    );
}
