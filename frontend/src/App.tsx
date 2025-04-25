import { useEffect } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import NameInput from './components/NameInput';
import { Scaffolding } from './components/Scaffolding';
import { Game } from './components/Game';
import { useAppStore } from './store';

export const MIN_PLAYERS = 2;

function App() {
    const { isConnected, receivedMessage, sendMessage, connect } =
        useWebSocket();

    useAppStore((s) => s.assignSendMessage)(sendMessage);

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);

    const handleGameInfo = useAppStore((s) => s.handleGameInfo);
    const handleTurnStart = useAppStore((s) => s.handleTurnStart);
    const handlePlayerUpdate = useAppStore((s) => s.handlePlayerUpdate);
    const handlePlayerGuessedCorrectly = useAppStore(
        (s) => s.handlePlayerGuessedCorrectly
    );
    const handleTurnEnd = useAppStore((s) => s.handleTurnEnd);
    const addChatMessage = useAppStore((s) => s.addChatMessage);
    const resetGameState = useAppStore((s) => s.resetGameState);

    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);

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

    useEffect(() => {
        if (receivedMessage) {
            console.log('Processing message in useEffect:', receivedMessage);

            switch (receivedMessage.type) {
                case 'gameInfo': {
                    handleGameInfo(receivedMessage);
                    break;
                }
                case 'playerUpdate': {
                    handlePlayerUpdate(receivedMessage);
                    break;
                }
                case 'turnStart': {
                    handleTurnStart(receivedMessage);
                    break;
                }
                case 'playerGuessedCorrectly': {
                    handlePlayerGuessedCorrectly(receivedMessage);
                    break;
                }
                case 'chat': {
                    addChatMessage(receivedMessage.payload);
                    break;
                }
                case 'drawEvent': {
                    break;
                }
                case 'turnEnd': {
                    handleTurnEnd(receivedMessage);
                    break;
                }
                case 'error': {
                    const payload = receivedMessage.payload;
                    if (!payload) {
                        console.error('Received error with null payload');
                        break;
                    }
                    addChatMessage({
                        senderName: 'System',
                        message: `Error: ${payload.message || 'Unknown error'}`,
                        isSystem: true,
                    });
                    break;
                }
                default:
                    console.warn('Received unknown message: ', receivedMessage);
            }
        }
    }, [receivedMessage, appState]);

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
