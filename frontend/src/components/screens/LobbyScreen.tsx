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
            store.sendMessage({ type: 'startGame', payload: null });
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
