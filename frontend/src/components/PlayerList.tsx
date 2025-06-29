import { For, Show } from 'solid-js';
import { Player } from '../messages';

interface PlayerListProps {
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
}

function PlayerList(props: PlayerListProps) {
    const players = () => props.players || [];
    const currentDrawerId = () => props.currentDrawerId || null;
    const hostId = () => props.hostId || null;

    return (
        <div class="-mr-2 flex-grow overflow-y-auto pr-2">
            <Show
                when={players().length > 0}
                fallback={<p class="text-gray-500 italic">No players yet...</p>}
            >
                <ul class="space-y-1">
                    <For each={players()}>
                        {(player) => {
                            const hasGuessedCorrectly = () => !!player.hasGuessedCorrectly;
                            const isCurrentDrawer = () => player.id === currentDrawerId();
                            const isHost = () => player.id === hostId();

                            const getClassNames = () => {
                                let classes = "flex items-center gap-2 rounded p-2 text-gray-800 transition-all duration-200";
                                if (isCurrentDrawer()) classes += " bg-blue-100 font-semibold";
                                if (hasGuessedCorrectly() && !isCurrentDrawer()) classes += " bg-green-200 text-green-800 font-medium";
                                if (isHost()) classes += " border border-yellow-500 font-semibold";
                                return classes;
                            };

                            const getTitle = () => {
                                if (isHost()) return `${player.name} (Host)`;
                                if (isCurrentDrawer()) return `${player.name} is drawing`;
                                if (hasGuessedCorrectly()) return `${player.name} (Guessed Correctly!)`;
                                return player.name;
                            };

                            return (
                                <li
                                    class={getClassNames()}
                                    title={getTitle()}
                                >
                                    <span class="inline-flex h-5 w-5 flex-shrink-0 items-center justify-center text-lg">
                                        <Show when={isCurrentDrawer()}>
                                            ✏️
                                        </Show>
                                        <Show when={hasGuessedCorrectly() && !isCurrentDrawer()}>
                                            <span class="text-green-600">✅</span>
                                        </Show>
                                    </span>
                                    <span class="flex-grow truncate">
                                        {player.name || player.id}
                                    </span>
                                    <span class="ml-auto flex-shrink-0 font-mono text-sm text-gray-600 pl-2">
                                        {player.score ?? 0}
                                    </span>
                                </li>
                            );
                        }}
                    </For>
                </ul>
            </Show>
        </div>
    );
}

export default PlayerList;
