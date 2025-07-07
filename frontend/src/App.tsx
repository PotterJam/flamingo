import { Flamingo } from './components/Flamingo';
import { FlamingoBackground } from './components/Background';
import { RoomConnection } from './components/RoomConnection';
import { WS_ROOT } from './hooks/useWebSocket';
import { onMount } from 'solid-js';
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
        <main class="m-auto w-screen">
            <FlamingoBackground />
            {store.roomId ? <Flamingo wsUrl={wsUrl()} /> : <RoomConnection />}
        </main>
    );
}

export default App;
