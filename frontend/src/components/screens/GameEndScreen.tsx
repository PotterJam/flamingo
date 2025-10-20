import { For, createMemo } from 'solid-js';
import { store } from '../../store';
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card';
import { DrawingCarousel } from '../DrawingCarousel';

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

    // Split drawings into left and right side (alternating)
    const leftDrawings = createMemo(() =>
        store.gameState.drawingHistories.filter((_, index) => index % 2 === 0)
    );

    const rightDrawings = createMemo(() =>
        store.gameState.drawingHistories.filter((_, index) => index % 2 === 1)
    );

    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center gap-6 p-6">
            {/* Left carousel */}
            <div class="flex-shrink-0">
                <DrawingCarousel drawings={leftDrawings()} side="left" />
            </div>

            {/* Center scoreboard */}
            <Card class="w-sm gap-2 bg-white flex-shrink-0">
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

            {/* Right carousel */}
            <div class="flex-shrink-0">
                <DrawingCarousel drawings={rightDrawings()} side="right" />
            </div>
        </div>
    );
};
