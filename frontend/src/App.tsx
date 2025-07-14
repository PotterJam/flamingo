import { Flamingo } from './components/Flamingo';
import { RoomConnection } from './components/RoomConnection';
import { WS_ROOT } from './hooks/useWebSocket';
import { onMount, Show } from 'solid-js';
import { soundManager } from './sound-manager';
import { store } from './store';

export const MIN_PLAYERS = 2;

function App() {
    const wsUrl = () =>
        `${WS_ROOT}/${store.roomId}?playerName=${store.selfName}`;

    onMount(() => {
        soundManager.loadSounds();
    });

    return (
        <main class="flex h-screen w-screen items-center justify-center">
            <Show when={store.roomId} fallback={<RoomConnection />}>
                <Flamingo wsUrl={wsUrl()} />
            </Show>
        </main>
    );
}

export default App;
