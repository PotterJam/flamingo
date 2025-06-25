import { Show } from 'solid-js';
import { useAppStore, actions } from '../../store';
import { OutlineButton } from '../buttons/OutlineButton';
import { PrimaryButton } from '../buttons/PrimaryButton';
import PlayerList from '../PlayerList';
import { CANVAS_HEIGHT } from '../Game';
import { MIN_PLAYERS } from '../../App';

export const LobbyScreen = () => {
    const store = useAppStore();

    const isHost = () => store.gameState.localPlayerId === store.gameState.hostId;
    const canHostStartGame = () => isHost() && store.gameState.players.length >= MIN_PLAYERS;

    const copyRoomName = () => {
        navigator.clipboard.writeText(store.roomId || '');
    };

    const handleStartGame = () => {
        if (canHostStartGame()) {
            store.sendMessage({ 
                type: 'startGame', 
                payload: { roundCount: store.roundCount } 
            });
        } else {
            console.warn('Start game attempted but conditions not met.');
        }
    };

    return (
        <div class="flex w-full flex-grow justify-center">
            <div
                class="flex w-full flex-shrink-0 flex-col items-center justify-center gap-4"
                style={{ "max-height": `${CANVAS_HEIGHT + 100}px` }}
            >
                <div class="flex flex-col gap-4 rounded-lg bg-white p-4 shadow-lg lg:order-1 lg:w-[250px]">
                    <h2 class="flex-shrink-0 border-b pb-2 text-xl font-semibold">
                        Players ({store.gameState.players.length})
                    </h2>
                    <div class="mb-4 min-h-0 flex-shrink overflow-y-auto">
                        <PlayerList
                            players={store.gameState.players}
                            currentDrawerId={store.gameState.currentDrawerId}
                            hostId={store.gameState.hostId}
                        />
                    </div>
                </div>

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
                                    onInput={(e) => actions.setRoundCount(parseInt(e.currentTarget.value))}
                                    class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer slider"
                                />
                                <div class="flex justify-between text-xs text-gray-500 mt-1">
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
        </div>
    );
};
