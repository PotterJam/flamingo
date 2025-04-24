import { useEffect, useCallback } from 'react';
import { useWebSocket, ErrorPayload } from './hooks/useWebSocket';

import NameInput from './components/NameInput';
import { create } from 'zustand/react';
import { Scaffolding } from './components/Scaffolding';
import { Game } from './components/Game';
import { immer } from 'zustand/middleware/immer';
import { ChatMessage, Player, SendMsg } from './messages';
import { ReceivedMsg } from './messages';

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
    turnEndTime: null,
};

type CurrentAppState =
    | 'active'
    | 'waiting'
    | 'connecting'
    | 'joining'
    | 'enterName';

export type AppState = {
    sendMessage: (message: SendMsg) => void;
    lastMessage: ReceivedMsg | null;

    appState: CurrentAppState;
    gameState: GameState;
};

export type AppActions = {
    assignSendMessage: (func: (message: SendMsg) => void) => void;
    setLastMessage: (message: ReceivedMsg) => void;

    setState: (newState: CurrentAppState) => void;

    resetGameState: () => void;

    setLocalPlayerId: (id: string) => void;
    setPlayers: (players: Player[]) => void;
    playerGuessedCorrect: (playerId: string) => void;
    resetPlayerGuesses: () => void;
    setHostId: (id: string) => void;
    setCurrentDrawer: (id: string) => void;
    setWord: (word: string) => void;
    addChatMessage: (message: ChatMessage) => void;
    setTurnEndTime: (time: number | null) => void;
};

export const useAppStore = create<AppState & AppActions>()(
    immer((set) => ({
        sendMessage: () => {},
        assignSendMessage: (func) =>
            set((s) => {
                s.sendMessage = func;
            }),
        lastMessage: null,
        setLastMessage: (message) =>
            set((s) => {
                s.lastMessage = message;
            }),

        appState: 'connecting',
        setState: (newState) => set((_) => ({ appState: newState })),

        gameState: initialGameState,

        resetGameState: () =>
            set((s) => {
                s.gameState = initialGameState;
            }),
        setLocalPlayerId: (id) =>
            set((s) => {
                s.gameState.localPlayerId = id;
            }),
        setPlayers: (players) =>
            set((s) => {
                s.gameState.players = players;
            }),
        playerGuessedCorrect: (playerId) =>
            set((s) => {
                s.gameState.players = s.gameState.players.map((p) =>
                    p.id === playerId ? { ...p, hasGuessedCorrectly: true } : p
                );
            }),
        resetPlayerGuesses: () =>
            set((s) => {
                s.gameState.players = s.gameState.players.map((p) => ({
                    ...p,
                    hasGuessedCorrectly: false,
                }));
            }),
        setHostId: (id) =>
            set((s) => {
                s.gameState.hostId = id;
            }),
        setCurrentDrawer: (id) =>
            set((s) => {
                s.gameState.currentDrawerId = id;
            }),
        setWord: (word) =>
            set((s) => {
                s.gameState.word = word;
            }),
        addChatMessage: (message) =>
            set((s) => {
                s.gameState.messages.push(message);
            }),
        setTurnEndTime: (time) =>
            set((s) => {
                s.gameState.turnEndTime = time;
            }),
    }))
);

function App() {
    const { isConnected, sendMessage, connect } = useWebSocket();

    useAppStore((s) => s.assignSendMessage)(sendMessage);
    const lastMessage = useAppStore((s) => s.lastMessage);

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);
    const resetGameState = useAppStore((s) => s.resetGameState);

    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);
    const setLocalPlayerId = useAppStore((s) => s.setLocalPlayerId);

    const players = useAppStore((s) => s.gameState.players);
    const setPlayers = useAppStore((s) => s.setPlayers);
    const playerGuessedCorrect = useAppStore((s) => s.playerGuessedCorrect);
    const resetPlayerGuesses = useAppStore((s) => s.resetPlayerGuesses);

    const hostId = useAppStore((s) => s.gameState.hostId);
    const setHostId = useAppStore((s) => s.setHostId);

    const currentDrawerId = useAppStore((s) => s.gameState.currentDrawerId);
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
        if (lastMessage) {
            console.log('Processing message in useEffect:', lastMessage);
            const message = lastMessage;

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
                    const payload = message.payload as unknown as ErrorPayload;
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
    }, [
        lastMessage,
        addChatMessage,
        localPlayerId,
        currentDrawerId,
        hostId,
        appState,
    ]);

    const handleNameSet = useCallback(
        (name: string) => {
            console.log('handleNameSet called with name:', name);
            if (name && isConnected) {
                sendMessage({ type: 'setName', payload: { name: name } });
                setAppState('joining');
                console.log("Sent setName, moved state to 'joining'.");
            } else {
                console.error(
                    'Cannot set name - invalid name or WebSocket disconnected.'
                );
            }
        },
        [isConnected, sendMessage]
    );

    if (appState === 'enterName') {
        return (
            <Scaffolding>
                <NameInput onNameSet={handleNameSet} />
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
