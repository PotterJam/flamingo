import { Component, For, Show, createMemo } from 'solid-js';
import { store } from '../store';
import { cn } from '../lib/utils/cn';

const PlayerList: Component = () => {
    const sortedPlayers = createMemo(() =>
        [...store.gameState.players].sort((a, b) =>
            a.name.localeCompare(b.name)
        )
    );

    return (
        <div class="-mr-2 flex-grow overflow-y-auto pr-2">
            <ul>
                <For each={sortedPlayers()}>
                    {(player) => {
                        const hasGuessedCorrectly = () =>
                            !!player.hasGuessedCorrectly;
                        const isCurrentDrawer = () =>
                            player.id === store.gameState.currentDrawerId;

                        const getClassNames = () => {
                            return cn(
                                'flex items-center gap-2 p-2 text-gray-800 transition-all duration-200',
                                isCurrentDrawer() &&
                                    'bg-yellow-100 font-semibold',
                                hasGuessedCorrectly() &&
                                    !isCurrentDrawer() &&
                                    'bg-green-200 text-green-800 font-medium'
                            );
                        };

                        return (
                            <li class={getClassNames()}>
                                <span class="inline-flex h-5 w-5 flex-shrink-0 items-center justify-center text-lg">
                                    <Show when={isCurrentDrawer()}>
                                        <span class="text-sm">✏️</span>
                                    </Show>
                                </span>
                                <span class="flex-grow truncate">
                                    {player.name || player.id}
                                </span>
                                <span class="ml-auto flex-shrink-0 pl-2 text-sm text-gray-600">
                                    {player.score ?? 0}
                                </span>
                            </li>
                        );
                    }}
                </For>
            </ul>
        </div>
    );
};

export default PlayerList;
