import { useEffect } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import { useAppStore } from './store';
import { useHandleMessage } from './components/event-wrapper';
import { Scaffolding } from './components/Scaffolding';
import NameInput from './components/NameInput';
import { Game } from './components/Game';

export const MIN_PLAYERS = 2;

function App() {
    const { isConnected, receivedMessage, sendMessage, connect } =
        useWebSocket();
    useHandleMessage(receivedMessage);

    const assignSendMessage = useAppStore((s) => s.assignSendMessage);

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);
    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);

    const resetGameState = useAppStore((s) => s.resetGameState);

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
    }, [isConnected, appState, connect]);

    if (appState === 'enterName') {
        return (
            <Scaffolding>
                <NameInput />
            </Scaffolding>
        );
    }

    if (!isConnected) {
        return (
            <Scaffolding>
                <div className="mt-10 text-center">Loading...</div>
            </Scaffolding>
        );
    }

    if (appState === 'joining' || !localPlayerId) {
        return (
            <Scaffolding>
                <div className="mt-10 text-center">
                    <p className="mt-2 animate-pulse text-gray-500">
                        Waiting for server info...
                    </p>
                </div>
            </Scaffolding>
        );
    }

    return (
        <Scaffolding>
            <Game />
        </Scaffolding>
    );
}

export default App;
