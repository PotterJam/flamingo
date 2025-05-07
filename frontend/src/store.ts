import { create } from 'zustand/react';
import {
    ChatMessage,
    DrawEvent,
    DrawEventMsg,
    GameInfoMsg,
    Player,
    PlayerUpdateMsg,
    ReceivedMsg,
    SendMsg,
    TurnEndMsg,
    TurnSetupMsg,
    TurnStartMsg,
    GameFinishedMsg,
} from './messages';
import { immer } from 'zustand/middleware/immer';
import { MIN_PLAYERS } from './App';
import { createJSONStorage, persist } from 'zustand/middleware';

export interface GameState {
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
    localPlayerId: string | null;
    word: string | null;
    wordLength: number | null;
    wordChoices: string[] | null;
    messages: ChatMessage[];
    turnEndTime: number | null;
    lastDrawEvent: DrawEvent | null;
}

export interface Room {
    roomId: string;
}

const initialGameState: GameState = {
    players: [],
    currentDrawerId: null,
    hostId: null,
    localPlayerId: null,
    word: null,
    wordChoices: null,
    wordLength: null,
    messages: [],
    turnEndTime: null,
    lastDrawEvent: null,
};

export type CurrentAppState =
    | 'active'
    | 'waiting'
    | 'connecting'
    | 'joining'
    | 'finished';

export type AppState = {
    sendMessage: (message: SendMsg) => void;
    lastMessage: ReceivedMsg | null;

    selfName: string;
    selfId: string;
    launchAsHost: boolean;

    appState: CurrentAppState;
    gameState: GameState;
    roomId: string | null;

    clearCanvas: (() => void) | null;
};

export type AppActions = {
    assignSendMessage: (func: (message: SendMsg) => void) => void;
    setLastMessage: (message: ReceivedMsg) => void;

    setState: (newState: CurrentAppState) => void;

    nameChosen: (name: string) => void;

    roomCreated: (roomId: string) => void;
    joinRoom: (roomId: string) => void;

    resetGameState: () => void;

    addChatMessage: (message: ChatMessage) => void;
    setClearCanvas: (callback: (() => void) | null) => void;
};

export type MessageHandlers = {
    handleGameInfo: (msg: GameInfoMsg) => void;
    handleTurnSetup: (msg: TurnSetupMsg) => void;
    handleTurnStart: (msg: TurnStartMsg) => void;
    handlePlayerUpdate: (msg: PlayerUpdateMsg) => void;
    handleTurnEnd: (msg: TurnEndMsg) => void;
    handleDraw: (msg: DrawEventMsg) => void;
    handleGameFinished: (msg: GameFinishedMsg) => void;
};

export const useAppStore = create<AppState & AppActions & MessageHandlers>()(
    persist(
        immer((set) => ({
            gameState: initialGameState,
            roomId: null,
            appState: 'connecting',
            selfName: '',
            selfId: '',
            launchAsHost: false,
            lastMessage: null,
            clearCanvas: null,

            sendMessage: () => {
                throw new Error('sending message without sender configured');
            },
            assignSendMessage: (func) =>
                set((s) => {
                    s.sendMessage = func;
                }),
            setLastMessage: (message) =>
                set((s) => {
                    s.lastMessage = message;
                }),
            setState: (newState) => set((_) => ({ appState: newState })),
            nameChosen: (name) =>
                set((s) => {
                    s.selfName = name;
                }),
            roomCreated: (room) =>
                set((s) => {
                    s.roomId = room;
                    s.launchAsHost = true;
                }),
            joinRoom: (roomId) =>
                set((s) => {
                    s.roomId = roomId;
                    s.launchAsHost = false;
                }),
            resetGameState: () =>
                set((s) => {
                    s.gameState = initialGameState;
                }),
            addChatMessage: (message) =>
                set((s) => {
                    s.gameState.messages.push(message);
                }),
            setClearCanvas: (callback) =>
                set((s) => {
                    s.clearCanvas = callback;
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
            handleTurnSetup: ({ payload }) =>
                set((s) => {
                    s.gameState.currentDrawerId = payload.currentDrawerId;
                    s.gameState.wordChoices = payload.wordChoices ?? null;
                    s.gameState.players = payload.players;
                    s.gameState.turnEndTime = payload.turnEndTime;

                    s.appState = 'active';
                }),
            handleTurnStart: ({ payload }) =>
                set((s) => {
                    s.gameState.wordChoices = null; // The word has been chosen

                    s.gameState.currentDrawerId = payload.currentDrawerId;
                    s.gameState.word = payload.word ?? null;
                    s.gameState.wordLength = payload.wordLength ?? null;
                    s.gameState.players = payload.players;
                    s.gameState.turnEndTime = payload.turnEndTime;

                    s.clearCanvas && s.clearCanvas();

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
            handleTurnEnd: ({ payload }) =>
                set((s) => {
                    s.gameState.players = payload.players;
                    s.gameState.turnEndTime = null;
                    s.gameState.word = null;
                    s.gameState.wordLength = null;
                    s.gameState.wordChoices = null;
                    s.gameState.currentDrawerId = null;
                }),
            handleDraw: ({ payload }) =>
                set((s) => {
                    s.gameState.lastDrawEvent = payload;
                }),
            handleGameFinished: ({ payload }) =>
                set((s) => {
                    s.appState = 'finished';
                    s.gameState.players = payload.players;
                    s.gameState.currentDrawerId = null;
                    s.gameState.word = null;
                    s.gameState.wordLength = null;
                    s.gameState.wordChoices = null;
                    s.gameState.turnEndTime = null;
                }),
        })),
        {
            name: 'flamingo-store',
            // session storage is used so that different tabs and sessions have separate state
            // this helps with dev time especially because different tabs can persist different stores
            storage: createJSONStorage(() => sessionStorage),
        }
    )
);
