import { FC } from 'react';
import { useAppStore } from '../../store';
import { OutlineButton } from '../buttons/OutlineButton';
import { PrimaryButton } from '../buttons/PrimaryButton';
import { CANVAS_HEIGHT } from '../Game';
import { MIN_PLAYERS } from '../../App';
import { PlayerList } from '../PlayerList';

export const LobbyScreen: FC = () => {
    const roomId = useAppStore((s) => s.roomId) ?? '';
    const sendMessage = useAppStore((s) => s.sendMessage);
    const { players, currentDrawerId, hostId, localPlayerId } = useAppStore(
        (s) => s.gameState
    );

    const isHost = localPlayerId === hostId;
    const canHostStartGame = isHost && players.length >= MIN_PLAYERS;

    const copyRoomName = () => {
        navigator.clipboard.writeText(roomId);
    };

    const handleStartGame = () => {
        if (canHostStartGame) {
            sendMessage({ type: 'startGame', payload: null });
        } else {
            console.warn('Start game attempted but conditions not met.');
        }
    };

    return (
        <div className="flex w-full flex-grow justify-center">
            <div
                className="flex w-full flex-shrink-0 flex-col items-center justify-center gap-4"
                style={{ maxHeight: `${CANVAS_HEIGHT + 100}px` }}
            >
                <div className="flex w-64 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1">
                    <h2 className="flex-shrink-0 text-xl font-semibold">
                        Lobby
                    </h2>
                    <PlayerList
                        showScore={false}
                        players={players}
                        currentDrawerId={currentDrawerId}
                    />
                </div>

                <div className="flex w-64 flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1">
                    {isHost && (
                        <div className="flex flex-row items-center justify-between">
                            <p className="text-l font-bold text-blue-400">
                                {roomId}
                            </p>
                            <OutlineButton
                                className="w-20"
                                onClick={() => copyRoomName()}
                            >
                                Copy
                            </OutlineButton>
                        </div>
                    )}
                    <PrimaryButton
                        onClick={handleStartGame}
                        disabled={!canHostStartGame}
                    >
                        Start Game
                    </PrimaryButton>
                </div>
            </div>
        </div>
    );
};
