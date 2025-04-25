import { useEffect, useCallback } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import NameInput from './components/NameInput';
import { Scaffolding } from './components/Scaffolding';
import { Game } from './components/Game';
import { ChatMessage } from './messages';
import { useAppStore } from './store';

const MIN_PLAYERS = 2;

function App() {
    const { isConnected, receivedMessage, sendMessage, connect } =
        useWebSocket();

    useAppStore((s) => s.assignSendMessage)(sendMessage);

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);
    const resetGameState = useAppStore((s) => s.resetGameState);

    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);
    const setLocalPlayerId = useAppStore((s) => s.setLocalPlayerId);

    const players = useAppStore((s) => s.gameState.players);
    const setPlayers = useAppStore((s) => s.setPlayers);
    const playerGuessedCorrect = useAppStore((s) => s.playerGuessedCorrect);
    const resetPlayerGuesses = useAppStore((s) => s.resetPlayerGuesses);

    const setHostId = useAppStore((s) => s.setHostId);

    const setCurrentDrawer = useAppStore((s) => s.setCurrentDrawer);

    const setWord = useAppStore((s) => s.setWord);

    const pushChatMessage = useAppStore((s) => s.addChatMessage);

    const setTurnEndTime = useAppStore((s) => s.setTurnEndTime);

    const addChatMessage = useCallback((msgPayload: ChatMessage) => {
        pushChatMessage(msgPayload);
    }, []);

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
            const message = receivedMessage;

            switch (message.type) {
                case 'gameInfo': {
                    const payload = message.payload;
                    setLocalPlayerId(payload.yourId);
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId);
                    payload.currentDrawerId &&
                        setCurrentDrawer(payload.currentDrawerId);
                    payload.turnEndTime && setTurnEndTime(payload.turnEndTime);

                    if (payload.isGameActive) {
                        setAppState('active');
                    } else {
                        setAppState('waiting');
                    }
                    console.log(
                        'Processed gameInfo. New State:',
                        payload.isGameActive ? 'active' : 'waiting',
                        'localId:',
                        payload.yourId
                    );
                    break;
                }
                case 'playerUpdate': {
                    const payload = message.payload;
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId);

                    if (
                        appState === 'active' &&
                        (payload.players?.length ?? 0) < MIN_PLAYERS
                    ) {
                        console.log(
                            'Player count dropped below minimum, returning to waiting state.'
                        );
                        setAppState('waiting');
                    }

                    break;
                }
                case 'turnStart': {
                    const payload = message.payload;
                    setCurrentDrawer(payload.currentDrawerId);
                    setWord(payload.word || '');
                    setPlayers(payload.players || players);
                    setTurnEndTime(payload.turnEndTime);
                    setAppState('active');
                    break;
                }
                case 'playerGuessedCorrectly': {
                    const payload = message.payload;
                    const { playerId } = payload;
                    playerGuessedCorrect(playerId);
                    const guesser = players.find((p) => p.id === playerId);
                    if (guesser) {
                        addChatMessage({
                            senderName: 'System',
                            message: `${guesser?.name ?? 'Unknown'} guessed the word!`,
                            isSystem: true,
                        });
                    }
                    break;
                }
                case 'chat': {
                    const payload = message.payload;
                    addChatMessage(payload);
                    break;
                }
                case 'drawEvent': {
                    break;
                }
                case 'turnEnd': {
                    setTurnEndTime(null);
                    resetPlayerGuesses();
                    break;
                }
                case 'error': {
                    const payload = message.payload;
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
                    console.warn('Received unknown message: ', message);
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
