import { useState, useEffect, useMemo, useCallback } from 'react';
import { useWebSocket, Player, ErrorPayload, TurnEndPayload } from './hooks/useWebSocket';

import NameInput from './components/NameInput';
import StatusMessage from './components/StatusMessage';
import { create } from 'zustand/react';
import { Scaffolding } from './components/Scaffolding';
import { Game } from './components/Game';
import { immer } from 'zustand/middleware/immer';

export interface ChatMessage {
    senderName: string;
    message: string;
    isSystem: boolean;
}

const MIN_PLAYERS = 2;

interface GameState {
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
    localPlayerId: string | null;
    word: string | null;
    messages: ChatMessage[];
    turnEndTime: number | null;
}

const initialGameState = {
    players: [],
    currentDrawerId: null,
    hostId: null,
    localPlayerId: null,
    word: null,
    messages: [],
    turnEndTime: null
};

type CurrentAppState = 'active'
    | 'waiting'
    | 'connecting'
    | 'joining'
    | 'enterName';

export type AppState = {
    appState: CurrentAppState;
    gameState: GameState;
}

export type AppActions = {
    setState: (newState: CurrentAppState) => void;
    resetGameState: () => void;
    setLocalPlayerId: (id: string) => void;
    setPlayers: (players: Player[]) => void;
    playerGuessedCorrect: (playerId: string) => void;
    resetPlayerGuesses: () => void;
}

export const useAppStore = create<AppState & AppActions>()(immer((set) => ({
    appState: 'connecting',
    setState: (newState) => set((_) => ({ appState: newState })),

    gameState: initialGameState,

    resetGameState: () => set((s) => { s.gameState = initialGameState }),
    setLocalPlayerId: (id) => set((state) => { if (state.gameState) state.gameState.localPlayerId = id }),
    setPlayers: (players) => set(s => s.gameState.players = players),
    playerGuessedCorrect: (playerId) => set(s =>
        s.gameState.players = s.gameState.players.map(p =>
            p.id === playerId ? { ...p, hasGuessedCorrectly: true } : p
        )
    ),
    resetPlayerGuesses: () => set(s => s.gameState.players = s.gameState.players.map(p => ({ ...p, hasGuessedCorrectly: false }))
    ),

})));

function App() {
    const { isConnected, lastMessage, sendMessage, connect } = useWebSocket();

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);
    const resetGameState = useAppStore(s => s.resetGameState);

    const localPlayerId = useAppStore(s => s.gameState.localPlayerId);
    const setLocalPlayerId = useAppStore(s => s.setLocalPlayerId);

    const players = useAppStore(s => s.gameState.players);
    const setPlayers = useAppStore(s => s.setPlayers);
    const playerGuessedCorrect = useAppStore(s => s.playerGuessedCorrect);
    const resetPlayerGuesses = useAppStore(s => s.resetPlayerGuesses);

    const [hostId, setHostId] = useState<string | null>(null);
    const [currentDrawerId, setCurrentDrawerId] = useState<string | null>(null);
    const [secretWord, setSecretWord] = useState('');
    const [wordLength, setWordLength] = useState(0);
    const [statusText, setStatusText] = useState('Connecting to server...');
    const [chatMessages, setChatMessages] = useState<ChatMessage[]>([]);
    const [turnEndTime, setTurnEndTime] = useState<number | null>(null);

    const addChatMessage = useCallback((msgPayload: ChatMessage) => {
        setChatMessages(prevMessages => {
            const newMessages = [...prevMessages, msgPayload];

            return newMessages.length > 100 ? newMessages.slice(-100) : newMessages;
        });
    }, []);

    useEffect(() => {
        if (isConnected) {
            if (appState === 'connecting') {
                console.log("WebSocket connected, moving to enterName state.");
                setAppState('enterName');
                setStatusText('Please enter your name.');
            }
        } else {
            if (appState !== 'connecting') {
                console.log("WebSocket disconnected.");
                setAppState('connecting');
                setStatusText('Disconnected. Trying to reconnect...');
                resetGameState();
                setHostId(null);
                setCurrentDrawerId(null);
                setSecretWord('');
                setWordLength(0);
                setChatMessages([]);
                setTurnEndTime(null);
            }
        }
    }, [isConnected, appState, connect]);

    useEffect(() => {
        if (lastMessage) {
            console.log("Processing message in useEffect:", lastMessage);
            const message = lastMessage;

            switch (message.type) {
                case 'gameInfo': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received gameInfo with null payload");
                        break;
                    }
                    setLocalPlayerId(payload.yourId);
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || null);
                    setCurrentDrawerId(payload.currentDrawerId || null);
                    setWordLength(payload.wordLength || 0);
                    setTurnEndTime(payload.turnEndTime || null);
                    setSecretWord('');

                    if (payload.isGameActive) {
                        setAppState('active');
                    } else {
                        setAppState('waiting');
                    }
                    console.log("Processed gameInfo. New State:", payload.isGameActive ? 'active' : 'waiting', "localId:", payload.yourId);
                    break;
                }
                case 'playerUpdate': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received playerUpdate with null payload");
                        break;
                    }
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || hostId);

                    if (appState === 'active' && (payload.players?.length ?? 0) < MIN_PLAYERS) {
                        console.log("Player count dropped below minimum, returning to waiting state.");
                        setCurrentDrawerId(null);
                        setTurnEndTime(null);
                        setWordLength(0);
                        setSecretWord('');
                        setAppState('waiting');
                    }

                    break;
                }
                case 'turnStart': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received turnStart with null payload");
                        break;
                    }
                    setCurrentDrawerId(payload.currentDrawerId);
                    setWordLength(payload.wordLength);
                    setSecretWord(payload.word || '');
                    setPlayers(payload.players || players);
                    setHostId(payload.players?.find(p => p.isHost)?.id || hostId);
                    setTurnEndTime(payload.turnEndTime);
                    setAppState('active');
                    break;
                }
                case 'playerGuessedCorrectly': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received playerGuessedCorrectly with null payload");
                        break;
                    }
                    const { playerId } = payload;
                    playerGuessedCorrect(playerId);
                    const guesser = players.find(p => p.id === playerId);
                    if (guesser) {
                        addChatMessage({
                            senderName: 'System',
                            message: `${guesser?.name ?? 'Unknown'} guessed the word!`,
                            isSystem: true
                        });
                    }
                    break;
                }
                case 'chat': {
                    const payload = message.payload as unknown as ChatMessage;
                    if (!payload) {
                        console.error("Received chat with null payload");
                        break;
                    }
                    addChatMessage(payload);
                    break;
                }
                case 'drawEvent': {
                    const payload = message.payload;
                    if (!payload) {
                        break;
                    }
                    break;
                }
                case 'turnEnd': {
                    const payload = message.payload as unknown as TurnEndPayload;
                    if (!payload) {
                        console.error("Received turnEnd with null payload");
                        break;
                    }
                    setTurnEndTime(null);
                    if (localPlayerId !== currentDrawerId) {
                        setWordLength(0);
                    }

                    setStatusText(`Word was: ${payload.correctWord}. Getting next turn ready...`);

                    resetPlayerGuesses();
                    break;
                }
                case 'error': {
                    const payload = message.payload as unknown as ErrorPayload;
                    if (!payload) {
                        console.error("Received error with null payload");
                        break;
                    }
                    setStatusText(`Error: ${payload.message || 'Unknown error'}`);
                    addChatMessage({
                        senderName: 'System',
                        message: `Error: ${payload.message || 'Unknown error'}`,
                        isSystem: true
                    });
                    break;
                }
                default:
                    console.warn("Received unhandled message type:", message.type);
            }
        }
    }, [lastMessage, addChatMessage, localPlayerId, currentDrawerId, hostId, appState]);

    const handleNameSet = useCallback((name: string) => {
        console.log("handleNameSet called with name:", name);
        if (name && isConnected) {
            sendMessage('setName', { name: name });
            setAppState('joining');
            setStatusText('Joining game... Please wait.');
            console.log("Sent setName, moved state to 'joining'.");
        } else {
            console.error("Cannot set name - invalid name or WebSocket disconnected.");
            setStatusText("Failed to set name. Please check connection and try again.");
        }
    }, [isConnected, sendMessage]);

    if (appState === 'enterName') {
        return (
            <Scaffolding>
                <NameInput onNameSet={handleNameSet} />
                <StatusMessage message={statusText} />
            </Scaffolding>
        );
    }

    if (!isConnected) {
        return (
            <Scaffolding>
                <div className="text-center mt-10">
                    <StatusMessage message={statusText} />
                </div>
            </Scaffolding>
        );
    }

    if (appState === 'joining' || !localPlayerId) {
        return (
            <Scaffolding>
                <div className="text-center mt-10">
                    <StatusMessage message={statusText} />
                    <p className="text-gray-500 animate-pulse mt-2">Waiting for server info...</p>
                </div>
            </Scaffolding>
        );
    }

    return (
        <Scaffolding>
            <Game />
        </Scaffolding >
    );
}

export default App;
