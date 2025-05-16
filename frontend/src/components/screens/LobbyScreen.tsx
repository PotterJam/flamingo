import { FC } from 'react';
import { useAppStore } from '../../store';
import { OutlineButton } from '../buttons/OutlineButton';
import { PrimaryButton } from '../buttons/PrimaryButton';
import PlayerList from '../PlayerList';
import { CANVAS_HEIGHT } from '../Game';
import { MIN_PLAYERS } from '../../App';

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
                <div className="flex flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]">
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
                </div>

                <div className="flex flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]">
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
