import { For } from 'solid-js';
import { store } from '../../store';
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card';

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
    const finalPlayers = [...store.gameState.players].sort((a, b) => b.score - a.score);

    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center">
            <Card class="w-sm gap-2 bg-white">
                <CardHeader>
                    <CardTitle class="text-2xl">Game complete</CardTitle>
                </CardHeader>
                <CardContent>
                    <ul>
                        <For each={finalPlayers}>
                            {(player, index) => (
                                <li class="flex items-center justify-between p-3 text-lg">
                                    <span class="flex items-center">
                                        <span class="mr-2 w-6 text-xl">
                                            {getMedal(index())}
                                        </span>
                                        <span class="font-medium text-gray-900">
                                            {player.name}
                                        </span>
                                    </span>
                                    <span class="font-semibold text-pink-500">
                                        {player.score}
                                    </span>
                                </li>
                            )}
                        </For>
                    </ul>
                </CardContent>
            </Card>
        </div>
    );
};
