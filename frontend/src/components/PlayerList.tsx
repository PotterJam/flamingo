import { FC } from 'react';
import { Player } from '../messages';

interface PlayerListProps {
    players: Player[];
    currentDrawerId: string | null;
    showScore: boolean;
}

interface PlayerEntryProps {
    player: Player;
    currentDrawerId: string | null;
    showScore: boolean;
}

const PlayerEntry: FC<PlayerEntryProps> = ({
    player,
    currentDrawerId,
    showScore,
}) => {
    const hasGuessedCorrectly = player.hasGuessedCorrectly;

    return (
        <li
            key={player.id}
            className={`flex items-center gap-2 rounded p-2 text-gray-800 transition-all duration-200 ${player.id === currentDrawerId ? 'bg-blue-100 font-semibold' : ''} ${hasGuessedCorrectly && player.id !== currentDrawerId ? 'bg-green-100' : ''} ${player.isHost ? 'border border-yellow-500 font-semibold' : ''}`}
        >
            {player.name}
            {showScore && (
                <span className="ml-auto flex-shrink-0 pl-2 font-mono text-sm text-gray-600">
                    {player.score ?? 0}
                </span>
            )}
        </li>
    );
};

export const PlayerList: FC<PlayerListProps> = ({
    players = [],
    currentDrawerId = null,
    showScore,
}) => {
    return (
        <div className="-mr-2 flex-grow overflow-y-auto pr-2">
            <ul className="space-y-1">
                {players.map((player) => (
                    <PlayerEntry
                        player={player}
                        currentDrawerId={currentDrawerId}
                        showScore={showScore}
                    />
                ))}
            </ul>
        </div>
    );
};
