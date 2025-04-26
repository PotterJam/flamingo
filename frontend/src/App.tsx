import { useEffect } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import { useAppStore } from './store';
import { useHandleMessage } from './hooks/useHandleMessage';
import { Flamingo } from './components/Scaffolding';
import { FlamingoBackground } from './components/Background';
import { RoomConnection } from './components/RoomConnection';

export const MIN_PLAYERS = 2;

function App() {
    const { isConnected, receivedMessage, sendMessage } = useWebSocket();
    useHandleMessage(receivedMessage);

    const assignSendMessage = useAppStore((s) => s.assignSendMessage);
    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);
    const resetGameState = useAppStore((s) => s.resetGameState);
    const room = useAppStore((s) => s.room);

    useEffect(() => assignSendMessage(sendMessage), [sendMessage]);

    useEffect(() => {
        if (isConnected) {
            if (appState === 'connecting') {
                console.log('WebSocket connected, moving to enterName state.');
                setAppState('enterName');
            }
        } else {
            if (appState !== 'connecting') {
                console.log('WebSocket disconnected.');
                resetGameState();
                setAppState('connecting');
            }
        }
    }, [isConnected, appState]);

    if (!isConnected) {
        return (
            <>
                <FlamingoBackground />
                <div className="mt-10 text-center">Loading...</div>
            </>
        );
    }

    return (
        <main className="m-auto w-screen">
            <FlamingoBackground />
            {room ? <Flamingo /> : <RoomConnection />}
        </main>
    );
}

export default App;
