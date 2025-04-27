import { useAppStore } from './store';
import { Flamingo } from './components/Flamingo';
import { FlamingoBackground } from './components/Background';
import { RoomConnection } from './components/RoomConnection';
import { WS_ROOT } from './hooks/useWebSocket';

export const MIN_PLAYERS = 2;

function App() {
    const roomId = useAppStore((s) => s.roomId);
    const playerName = useAppStore((s) => s.selfName);

    const wsUrl = `${WS_ROOT}/${roomId}?playerName=${playerName}`;

    return (
        <main className="m-auto w-screen">
            <FlamingoBackground />
            {roomId ? <Flamingo wsUrl={wsUrl} /> : <RoomConnection />}
        </main>
    );
}

export default App;
