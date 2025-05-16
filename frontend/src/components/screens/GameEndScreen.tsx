import { FC } from 'react';
import { useAppStore } from '../../store';

const getMedal = (index: number): string => {
    switch (index) {
        case 0:
            return '🥇';
        case 1:
            return '🥈';
        case 2:
            return '🥉';
        default:
            return '';
    }
};

export const GameEndScreen: FC = () => {
    const players = useAppStore((s) => s.gameState.players);
    const sortedPlayers = [...players].sort((a, b) => b.score - a.score);

    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
            <div className="w-full max-w-md rounded-lg bg-white p-8 text-center shadow-xl">
                <h1 className="mb-6 text-4xl font-bold text-gray-800">
                    Game Over!
                </h1>
                <h2 className="mb-4 text-2xl font-semibold text-gray-700">
                    Final Scores:
                </h2>
                <ul className="space-y-3">
                    {sortedPlayers.map((player, index) => (
                        <li
                            key={player.id}
                            className="flex items-center justify-between rounded-md bg-gray-100 p-3 text-lg shadow-sm"
                        >
                            <span className="flex items-center">
                                <span className="mr-3 w-6 text-xl">
                                    {getMedal(index)}
                                </span>
                                <span className="font-medium text-gray-900">
                                    {player.name}
                                </span>
                            </span>
                            <span className="font-semibold text-blue-600">
                                {player.score} pts
                            </span>
                        </li>
                    ))}
                </ul>
            </div>
        </div>
    );
};

