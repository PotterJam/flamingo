import { create } from 'zustand/react';
import {
    ChatMessage,
    GameInfoMsg,
    Player,
    PlayerGuessedCorrectlyMsg,
    PlayerUpdateMsg,
    ReceivedMsg,
    SendMsg,
    TurnEndMsg,
    TurnStartMsg,
} from './messages';
import { immer } from 'zustand/middleware/immer';
import { MIN_PLAYERS } from './App';

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

export type MessageHandlers = {
    handleGameInfo: (msg: GameInfoMsg) => void;
    handleTurnStart: (msg: TurnStartMsg) => void;
    handlePlayerUpdate: (msg: PlayerUpdateMsg) => void;
    handlePlayerGuessedCorrectly: (msg: PlayerGuessedCorrectlyMsg) => void;
    handleTurnEnd: (msg: TurnEndMsg) => void;
};

export const useAppStore = create<AppState & AppActions & MessageHandlers>()(
    immer((set) => ({
        sendMessage: () => {
            throw new Error('sending message without sender configured');
        },
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

        // Message receivers
        handleGameInfo: ({ payload }) =>
            set((s) => {
                s.gameState.localPlayerId = payload.yourId;
                s.gameState.players = payload.players;
                s.gameState.hostId = payload.hostId;
                if (payload.currentDrawerId)
                    s.gameState.currentDrawerId = payload.currentDrawerId;
                if (payload.turnEndTime)
                    s.gameState.turnEndTime = payload.turnEndTime;

                if (payload.isGameActive) {
                    s.appState = 'active';
                } else {
                    s.appState = 'waiting';
                }
            }),
        handleTurnStart: ({ payload }) =>
            set((s) => {
                s.gameState.currentDrawerId = payload.currentDrawerId;
                s.gameState.word = payload.word ?? null;
                s.gameState.players = payload.players;
                s.gameState.turnEndTime = payload.turnEndTime;

                s.appState = 'active';
            }),
        handlePlayerUpdate: ({ payload }) =>
            set((s) => {
                s.gameState.players = payload.players;
                s.gameState.hostId = payload.hostId;

                if (
                    s.appState === 'active' &&
                    payload.players.length < MIN_PLAYERS
                ) {
                    console.log(
                        'Player count too small, going back to waiting'
                    );
                    s.appState = 'waiting';
                }
            }),
        handlePlayerGuessedCorrectly: ({ payload }) =>
            set((s) => {
                s.gameState.players = s.gameState.players.map((p) =>
                    p.id === payload.playerId
                        ? { ...p, hasGuessedCorrectly: true }
                        : p
                );
                const guesser = s.gameState.players.find(
                    (p) => p.id === payload.playerId
                );
                if (guesser) {
                    s.addChatMessage({
                        senderName: 'System',
                        message: `${guesser?.name ?? 'Unknown'} guessed the word!`,
                        isSystem: true,
                    });
                }
            }),
        handleTurnEnd: (_msg) =>
            set((s) => {
                s.gameState.turnEndTime = null;
                s.resetPlayerGuesses();
            }),
    }))
);
