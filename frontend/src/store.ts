import { create } from 'zustand/react';
import {
    ChatMessage,
    DrawEvent,
    DrawEventMsg,
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
    lastDrawEvent: DrawEvent | null;
}

export interface Room {
    roomId: string;
    roomSlug: string;
}

const initialGameState: GameState = {
    players: [],
    currentDrawerId: null,
    hostId: null,
    localPlayerId: null,
    word: null,
    messages: [],
    turnEndTime: null,
    lastDrawEvent: null,
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
    room: Room | null;
};

export type AppActions = {
    assignSendMessage: (func: (message: SendMsg) => void) => void;
    setLastMessage: (message: ReceivedMsg) => void;

    setState: (newState: CurrentAppState) => void;

    roomCreated: (room: Room) => void;

    resetGameState: () => void;

    resetPlayerGuesses: () => void;
    addChatMessage: (message: ChatMessage) => void;
};

export type MessageHandlers = {
    handleGameInfo: (msg: GameInfoMsg) => void;
    handleTurnStart: (msg: TurnStartMsg) => void;
    handlePlayerUpdate: (msg: PlayerUpdateMsg) => void;
    handlePlayerGuessedCorrectly: (msg: PlayerGuessedCorrectlyMsg) => void;
    handleTurnEnd: (msg: TurnEndMsg) => void;
    handleDraw: (msg: DrawEventMsg) => void;
};

export const useAppStore = create<AppState & AppActions & MessageHandlers>()(
    immer((set) => ({
        gameState: initialGameState,
        room: null,
        appState: 'connecting',

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

        setState: (newState) => set((_) => ({ appState: newState })),

        roomCreated: (room) =>
            set((s) => {
                s.room = room;
            }),

        resetGameState: () =>
            set((s) => {
                s.gameState = initialGameState;
            }),
        resetPlayerGuesses: () =>
            set((s) => {
                s.gameState.players = s.gameState.players.map((p) => ({
                    ...p,
                    hasGuessedCorrectly: false,
                }));
            }),
        addChatMessage: (message) =>
            set((s) => {
                s.gameState.messages.push(message);
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
        handleDraw: ({ payload }) =>
            set((s) => {
                s.gameState.lastDrawEvent = payload;
            }),
    }))
);
