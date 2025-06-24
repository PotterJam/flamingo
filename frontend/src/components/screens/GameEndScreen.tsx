import { For, createMemo } from 'solid-js';
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

export const GameEndScreen = () => {
    const store = useAppStore();
    const sortedPlayers = createMemo(() => 
        [...store.gameState.players].sort((a, b) => b.score - a.score)
    );

    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center">
            <div class="w-full max-w-md rounded-lg bg-white p-8 text-center shadow-xl">
                <h1 class="mb-6 text-4xl font-bold text-gray-800">
                    Game Over!
                </h1>
                <h2 class="mb-4 text-2xl font-semibold text-gray-700">
                    Final Scores:
                </h2>
                <ul class="space-y-3">
                    <For each={sortedPlayers()}>
                        {(player, index) => (
                            <li class="flex items-center justify-between rounded-md bg-gray-100 p-3 text-lg shadow-sm">
                                <span class="flex items-center">
                                    <span class="mr-3 w-6 text-xl">
                                        {getMedal(index())}
                                    </span>
                                    <span class="font-medium text-gray-900">
                                        {player.name}
                                    </span>
                                </span>
                                <span class="font-semibold text-blue-600">
                                    {player.score} pts
                                </span>
                            </li>
                        )}
                    </For>
                </ul>
            </div>
        </div>
    );
};

