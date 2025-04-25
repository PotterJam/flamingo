import { useEffect } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import { useAppStore } from './store';
import { EventWrapper } from './components/event-wrapper';

export const MIN_PLAYERS = 2;

function App() {
    const { isConnected, receivedMessage, sendMessage, connect } =
        useWebSocket();
    const assignSendMessage = useAppStore((s) => s.assignSendMessage);

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);

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

    return (
        <EventWrapper
            isConnected={isConnected}
            receivedMessage={receivedMessage}
        />
    );
}

export default App;
