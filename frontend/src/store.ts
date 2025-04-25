import { create } from 'zustand/react';
import { ChatMessage, Player, ReceivedMsg, SendMsg } from './messages';
import { immer } from 'zustand/middleware/immer';

export interface GameState {
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

export type CurrentAppState =
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
        sendMessage: () => { throw new Error('sending message without sender configured') },
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
