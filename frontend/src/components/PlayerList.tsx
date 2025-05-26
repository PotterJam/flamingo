import { FC } from 'react';
import { Player } from '../messages';

interface PlayerListProps {
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
}

export const PlayerList: FC<PlayerListProps> = ({
    players = [],
    currentDrawerId = null,
    hostId = null,
}) => {
    return (
        <div className="-mr-2 flex-grow overflow-y-auto pr-2">
            <ul className="space-y-1">
                {players.map((player) => {
                    const hasGuessedCorrectly = !!player.hasGuessedCorrectly;

                    return (
                        <li
                            key={player.id}
                            className={`flex items-center gap-2 rounded p-2 text-gray-800 transition-all duration-200 ${player.id === currentDrawerId ? 'bg-blue-100 font-semibold' : ''} ${hasGuessedCorrectly && player.id !== currentDrawerId ? 'bg-green-100' : ''} ${player.id === hostId ? 'border border-yellow-500 font-semibold' : ''}`}
                            title={
                                player.id === hostId
                                    ? `${player.name} (Host)`
                                    : player.id === currentDrawerId
                                      ? `${player.name} is drawing`
                                      : hasGuessedCorrectly
                                        ? `${player.name} (Guessed Correctly!)`
                                        : player.name
                            }
                        >
                            <span className="inline-flex h-5 w-5 flex-shrink-0 items-center justify-center text-lg">
                                {player.id === hostId ? (
                                    '👑'
                                ) : player.id === currentDrawerId ? (
                                    '✏️'
                                ) : hasGuessedCorrectly ? (
                                    <span className="text-green-600">✅</span>
                                ) : (
                                    ''
                                )}
                            </span>
                            <span className="flex-grow truncate">
                                {player.name || player.id}
                            </span>
                            <span className="ml-auto flex-shrink-0 pl-2 font-mono text-sm text-gray-600">
                                {player.score ?? 0}
                            </span>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
};
