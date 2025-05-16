import { FC } from 'react';
import { useAppStore } from '../../store';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../Game';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import WordDisplay from '../WordDisplay';
import TimerDisplay from '../TimerDisplay';
import Whiteboard from '../Whiteboard';
import GuessInput from '../GuessInput';
import { DrawEvent } from '../../messages';

export const GuessingScreen: FC = () => {
    const sendMessage = useAppStore((s) => s.sendMessage);
    const {
        players,
        currentDrawerId,
        hostId,
        localPlayerId,
        word,
        wordLength,
        turnEndTime,
    } = useAppStore((s) => s.gameState);

    const localPlayer = players.find((p) => p.id === localPlayerId);
    if (!localPlayer) {
        throw new Error('no local player found');
    }

    const isLocalPlayerDrawer = localPlayerId === currentDrawerId;
    const canLocalPlayerGuess =
        !isLocalPlayerDrawer && !localPlayer.hasGuessedCorrectly;

    const handleDraw = (drawData: DrawEvent) => {
        if (isLocalPlayerDrawer) {
            sendMessage({ type: 'drawEvent', payload: drawData });
        }
    };

    const handleGuess = (guess: string) => {
        if (canLocalPlayerGuess) {
            sendMessage({ type: 'guess', payload: { guess: guess } });
        }
    };

    return (
        <div className="flex w-full flex-grow justify-center">
            <div
                className="flex flex-col gap-4 lg:flex-row"
                style={{ width: `${250 + CANVAS_WIDTH + 32}px` }}
            >
                <aside
                    className="flex w-full flex-shrink-0 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]"
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

                    <h2
                        className={`flex-shrink-0 border-b pb-2 text-xl font-semibold`}
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
                            ) : currentDrawerId ? (
                                <WordDisplay
                                    blanks={Array(wordLength || '')
                                        .fill('_')
                                        .join(' ')}
                                    length={wordLength ?? 0}
                                />
                            ) : (
                                <div className="h-8 md:h-10"></div>
                            )}
                        </div>
                        <div className="w-20 flex-shrink-0 text-right">
                            {turnEndTime && (
                                <TimerDisplay endTime={turnEndTime} />
                            )}
                        </div>
                    </div>
                    <div className="relative mb-4 overflow-hidden bg-white">
                        <Whiteboard
                            isDrawer={isLocalPlayerDrawer}
                            onDraw={handleDraw}
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
