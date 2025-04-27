import { useAppStore } from './store';
import { Flamingo } from './components/Flamingo';
import { FlamingoBackground } from './components/Background';
import { RoomConnection } from './components/RoomConnection';

export const MIN_PLAYERS = 2;

function App() {
    const room = useAppStore((s) => s.room);

    return (
        <main className="m-auto w-screen">
            <FlamingoBackground />
            {room ? <Flamingo roomId={room.roomId} /> : <RoomConnection />}
        </main>
    );
}

export default App;
