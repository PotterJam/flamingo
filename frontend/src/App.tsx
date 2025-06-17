import { useAppStore } from './store';
import { Flamingo } from './components/Flamingo';
import { FlamingoBackground } from './components/Background';
import { RoomConnection } from './components/RoomConnection';
import { WS_ROOT } from './hooks/useWebSocket';

export const MIN_PLAYERS = 2;

function App() {
    const store = useAppStore();

    const wsUrl = () => `${WS_ROOT}/${store.roomId}?playerName=${store.selfName}`;

    return (
        <main class="m-auto w-screen">
            <FlamingoBackground />
            {store.roomId ? <Flamingo wsUrl={wsUrl()} /> : <RoomConnection />}
        </main>
    );
}

export default App;
