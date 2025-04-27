import { FC, useCallback } from 'react';
import { useAppStore } from '../store';
import PlayerList from './PlayerList';
import ChatBox from './ChatBox';
import WordDisplay from './WordDisplay';
import TimerDisplay from './TimerDisplay';
import Whiteboard from './Whiteboard';
import GuessInput from './GuessInput';
import { PrimaryButton } from './buttons/PrimaryButton';

const CANVAS_WIDTH = 800;
const CANVAS_HEIGHT = 600;
const MIN_PLAYERS = 2;

export const Game: FC = () => {
    const roomId = useAppStore((s) => s.roomId) ?? '';
    const sendMessage = useAppStore((s) => s.sendMessage);
    const appState = useAppStore((s) => s.appState);
    const gameState = useAppStore((s) => s.gameState);
    if (gameState === null) {
        return <div>sad</div>;
    }
    const {
        players,
        currentDrawerId,
        hostId,
        localPlayerId,
        word,
        turnEndTime,
    } = gameState;

    console.log(
        `players: ${players}, currentDrawerId: ${currentDrawerId}, hostId: ${hostId}, localId: ${localPlayerId}, word: ${word}, turnEnd: ${turnEndTime}`
    );

    const localPlayer = players.find((p) => p.id === localPlayerId);
    if (!localPlayer) {
        throw new Error('no local player found');
    }
    const isHost = localPlayerId === hostId;
    const isLocalPlayerDrawer = localPlayerId === currentDrawerId;
    const canHostStartGame =
        isHost && appState === 'waiting' && players.length >= MIN_PLAYERS;

    const canLocalPlayerGuess =
        !isLocalPlayerDrawer && !localPlayer.hasGuessedCorrectly;

    const wordBlanks = Array(word?.length || '')
        .fill('_')
        .join(' ');

    const handleStartGame = useCallback(() => {
        console.log('Start Game button clicked by host.');
        if (canHostStartGame) {
            sendMessage({ type: 'startGame', payload: null });
        } else {
            console.warn('Start game attempted but conditions not met.');
        }
    }, [canHostStartGame, sendMessage]);

    const handleDraw = useCallback(
        (drawData: any) => {
            if (isLocalPlayerDrawer && appState === 'active') {
                sendMessage({ type: 'drawEvent', payload: drawData });
            }
        },
        [isLocalPlayerDrawer, appState, sendMessage]
    );

    const handleGuess = useCallback(
        (guess: string) => {
            if (canLocalPlayerGuess) {
                sendMessage({ type: 'guess', payload: { guess: guess } });
            }
        },
        [canLocalPlayerGuess, sendMessage]
    );

    return (
        <div className="flex w-full flex-grow justify-center">
            <h2>{roomId}</h2>
            <div
                className="flex flex-col gap-4 lg:flex-row"
                style={{ width: `${250 + CANVAS_WIDTH + 32}px` }}
            >
                <aside
                    className="order-2 flex w-full flex-shrink-0 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]"
                    style={{ maxHeight: `${CANVAS_HEIGHT + 100}px` }}
                >
                    <h2 className="flex-shrink-0 border-b pb-2 text-xl font-semibold">
                        Players ({players.length})
                    </h2>
                    <div className="mb-4 min-h-0 flex-shrink overflow-y-auto">
                        <PlayerList
                            players={players}
                            currentDrawerId={currentDrawerId}
                            hostId={hostId}
                        />
                    </div>

                    {canHostStartGame && (
                        <PrimaryButton onClick={handleStartGame}>
                            Start Game
                        </PrimaryButton>
                    )}

                    <h2
                        className={`flex-shrink-0 border-b pb-2 text-xl font-semibold ${!canHostStartGame ? 'mt-auto' : ''}`}
                    >
                        Chat
                    </h2>
                    <div className="min-h-0 flex-grow overflow-y-hidden">
                        <ChatBox />
                    </div>
                </aside>

                <section className="order-1 flex w-full flex-col rounded-lg bg-white p-6 shadow-lg lg:order-2 lg:flex-1">
                    <div className="mb-4 flex flex-shrink-0 items-center justify-between gap-4">
                        <div className="min-w-0 flex-1 text-center">
                            {isLocalPlayerDrawer ? (
                                <WordDisplay word={word ?? ''} />
                            ) : appState === 'active' && currentDrawerId ? (
                                <WordDisplay
                                    blanks={wordBlanks}
                                    length={word?.length ?? 0}
                                />
                            ) : (
                                <div className="h-8 md:h-10"></div>
                            )}
                        </div>
                        <div className="w-20 flex-shrink-0 text-right">
                            {appState === 'active' && turnEndTime && (
                                <TimerDisplay endTime={turnEndTime} />
                            )}
                        </div>
                    </div>
                    <div
                        className="relative mb-4 overflow-hidden rounded border-2 border-black bg-white"
                        style={{
                            width: `${CANVAS_WIDTH}px`,
                            height: `${CANVAS_HEIGHT}px`,
                        }}
                    >
                        <Whiteboard
                            isDrawer={!!isLocalPlayerDrawer}
                            onDraw={handleDraw}
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
        </div>
    );
};
