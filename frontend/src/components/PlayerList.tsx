import { Player } from '../messages';

function PlayerList({
    players = [],
    currentDrawerId = null,
    hostId = null,
}: {
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
}) {
    return (
        <div className="-mr-2 flex-grow overflow-y-auto pr-2">
            {players.length === 0 ? (
                <p className="text-gray-500 italic">No players yet...</p>
            ) : (
                <ul className="space-y-1">
                    {players.map((player) => (
                        <li
                            key={player.id}
                            className={`flex items-center gap-2 rounded p-2 text-gray-800 transition-all duration-200 ${player.id === currentDrawerId ? 'bg-blue-100 font-semibold' : ''} ${player.hasGuessedCorrectly && player.id !== currentDrawerId ? 'bg-green-100' : ''} ${player.id === hostId ? 'border border-yellow-500 font-semibold' : ''} `}
                            title={
                                player.id === hostId
                                    ? `${player.name} (Host)`
                                    : player.id === currentDrawerId
                                      ? `${player.name} is drawing`
                                      : player.hasGuessedCorrectly
                                        ? `${player.name} guessed correctly!`
                                        : player.name
                            }
                        >
                            <span className="inline-flex h-5 w-5 flex-shrink-0 items-center justify-center text-lg">
                                {player.id === hostId ? (
                                    '👑'
                                ) : player.id === currentDrawerId ? (
                                    '✏️'
                                ) : player.hasGuessedCorrectly ? (
                                    <span className="text-green-600">✅</span>
                                ) : (
                                    ''
                                )}
                            </span>
                            <span className="flex-grow truncate">
                                {player.name || player.id}
                            </span>
                        </li>
                    ))}
                </ul>
            )}
        </div>
    );
}

export default PlayerList;
