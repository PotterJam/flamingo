import { Player } from "../messages";

function PlayerList({ players = [], currentDrawerId = null, hostId = null }: { players: Player[], currentDrawerId: string | null, hostId: string | null }) {
    return (
        <div className="flex-grow overflow-y-auto pr-2 -mr-2"> {/* Adjust padding/margin for scrollbar */}
            {players.length === 0 ? (
                <p className="text-gray-500 italic">No players yet...</p>
            ) : (
                <ul className="space-y-1">
                    {players.map(player => (
                        <li
                            key={player.id}
                            className={`p-2 rounded transition-all duration-200 flex items-center gap-2 text-gray-800
                                ${player.id === currentDrawerId ? 'bg-blue-100 font-semibold' : ''}
                                ${player.hasGuessedCorrectly && player.id !== currentDrawerId ? 'bg-green-100' : ''}
                                ${player.id === hostId ? 'border border-yellow-500 font-semibold' : ''}
                            `}
                            title={player.id === hostId ? `${player.name} (Host)` : (player.id === currentDrawerId ? `${player.name} is drawing` : (player.hasGuessedCorrectly ? `${player.name} guessed correctly!` : player.name))}
                        >
                            {/* Icon */}
                            <span className="w-5 h-5 inline-flex items-center justify-center text-lg flex-shrink-0">
                                {player.id === hostId ? '👑' :
                                    player.id === currentDrawerId ? '✏️' :
                                        player.hasGuessedCorrectly ? <span className="text-green-600">✅</span> : ''}
                            </span>
                            {/* Name */}
                            <span className="flex-grow truncate">{player.name || player.id}</span>
                            {/* Score (Placeholder) */}
                            {/* <span className="ml-auto font-mono text-sm text-gray-500">{player.score || 0}</span> */}
                        </li>
                    ))}
                </ul>
            )}
        </div>
    );
}

export default PlayerList;
