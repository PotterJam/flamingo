import { createMemo, For, Show } from 'solid-js';
import { actions, store } from '../../store';
import { OutlineButton } from '../buttons/OutlineButton';
import { PrimaryButton } from '../buttons/PrimaryButton';
import PlayerList from '../PlayerList';
import { CANVAS_HEIGHT } from '../Game';
import { MIN_PLAYERS } from '../../App';
import { Card } from '../ui/card';

export const LobbyScreen = () => {
    const isHost = () =>
        store.gameState.localPlayerId === store.gameState.hostId;
    const canHostStartGame = () =>
        isHost() && store.gameState.players.length >= MIN_PLAYERS;

    const copyRoomName = () => {
        navigator.clipboard.writeText(store.roomId || '');
    };

    const handleStartGame = () => {
        if (canHostStartGame()) {
            store.sendMessage({
                type: 'startGame',
                payload: { roundCount: store.roundCount },
            });
        } else {
            console.warn('Start game attempted but conditions not met.');
        }
    };

    return (
        <div class="flex h-full w-full flex-grow items-center justify-center">
            <Card class="flex h-4/5 w-full max-w-2xl flex-row bg-white p-0">
                <div class="flex flex-1 flex-col gap-4 border-r-2 border-black p-4">
                    <h2 class="text-xl font-bold">Players</h2>
                    <div class="overflowy-auto h-full">
                        <ul class="space-y-2">
                            <For each={store.gameState.players}>
                                {(player) => {
                                    return <li>{player.name}</li>;
                                }}
                            </For>
                        </ul>
                    </div>
                </div>
                <div
                    class="flex w-full flex-3 flex-col items-center justify-center gap-4"
                    style={{ 'max-height': `${CANVAS_HEIGHT + 100}px` }}
                >
                    <div class="flex flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]">
                        <Show when={isHost()}>
                            <div class="flex flex-row items-center justify-between">
                                <p class="text-l font-bold text-blue-400">
                                    {store.roomId}
                                </p>
                                <OutlineButton
                                    class="w-20"
                                    onClick={copyRoomName}
                                >
                                    Copy
                                </OutlineButton>
                            </div>
                        </Show>

                        <Show when={isHost()}>
                            <div class="flex flex-col gap-2">
                                <label class="text-sm font-medium text-gray-700">
                                    Rounds: {store.roundCount}
                                </label>
                                <div class="relative">
                                    <input
                                        type="range"
                                        min="1"
                                        max="5"
                                        value={store.roundCount}
                                        onInput={(e) =>
                                            actions.setRoundCount(
                                                parseInt(e.currentTarget.value)
                                            )
                                        }
                                        class="slider h-2 w-full cursor-pointer appearance-none rounded-lg bg-gray-200"
                                    />
                                    <div class="mt-1 flex justify-between text-xs text-gray-500">
                                        <span>1</span>
                                        <span>2</span>
                                        <span>3</span>
                                        <span>4</span>
                                        <span>5</span>
                                    </div>
                                </div>
                            </div>
                        </Show>

                        <PrimaryButton
                            onClick={handleStartGame}
                            disabled={!canHostStartGame()}
                        >
                            Start Game
                        </PrimaryButton>
                    </div>
                </div>
            </Card>
        </div>
    );
};
