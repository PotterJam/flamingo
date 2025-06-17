import { createStore } from 'solid-js/store';
import { createEffect } from 'solid-js';
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
import { GamePhase } from './model';

export interface GameState {
    gamePhase: GamePhase;
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

const initialGameState: GameState = {
    gamePhase: 'Lobby',
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

export interface AppState {
    sendMessage: (message: SendMsg) => void;
    lastMessage: ReceivedMsg | null;
    selfName: string;
    selfId: string;
    launchAsHost: boolean;
    gameState: GameState;
    roomId: string | null;
    clearCanvas: (() => void) | null;
}

const initialAppState: AppState = {
    sendMessage: () => {
        throw new Error('sending message without sender configured');
    },
    lastMessage: null,
    selfName: '',
    selfId: '',
    launchAsHost: false,
    gameState: initialGameState,
    roomId: null,
    clearCanvas: null,
};

const getStoredState = (): Partial<AppState> => {
    try {
        const stored = sessionStorage.getItem('flamingo-store');
        return stored ? JSON.parse(stored) : {};
    } catch {
        return {};
    }
};

const [store, setStore] = createStore<AppState>({
    ...initialAppState,
    ...getStoredState(),
});

createEffect(() => {
    sessionStorage.setItem('flamingo-store', JSON.stringify(store));
});

export const useAppStore = () => store;

export const actions = {
    assignSendMessage: (func: (message: SendMsg) => void) => {
        setStore('sendMessage', func);
    },

    setLastMessage: (message: ReceivedMsg) => {
        setStore('lastMessage', message);
    },

    setState: (newState: GamePhase) => {
        setStore('gameState', 'gamePhase', newState);
    },

    nameChosen: (name: string) => {
        setStore('selfName', name);
    },

    roomCreated: (room: string) => {
        setStore('roomId', room);
        setStore('launchAsHost', true);
    },

    joinRoom: (roomId: string) => {
        setStore('roomId', roomId);
        setStore('launchAsHost', false);
    },

    resetGameState: () => {
        setStore('gameState', initialGameState);
    },

    addChatMessage: (message: ChatMessage) => {
        setStore('gameState', 'messages', (messages: ChatMessage[]) => [...messages, message]);
    },

    setClearCanvas: (callback: (() => void) | null) => {
        setStore('clearCanvas', callback);
    },

    handleGameInfo: ({ payload }: GameInfoMsg) => {
        setStore('gameState', {
            localPlayerId: payload.yourId,
            players: payload.players,
            hostId: payload.hostId,
            ...(payload.currentDrawerId && { currentDrawerId: payload.currentDrawerId }),
            ...(payload.turnEndTime && { turnEndTime: payload.turnEndTime }),
        });
    },

    handleTurnSetup: ({ payload }: TurnSetupMsg) => {
        setStore('gameState', {
            currentDrawerId: payload.currentDrawerId,
            wordChoices: payload.wordChoices ?? null,
            players: payload.players,
            turnEndTime: payload.turnEndTime,
            gamePhase: 'WordChoice' as GamePhase,
        });
    },

    handleTurnStart: ({ payload }: TurnStartMsg) => {
        setStore('gameState', {
            wordChoices: null,
            currentDrawerId: payload.currentDrawerId,
            word: payload.word ?? null,
            wordLength: payload.wordLength ?? null,
            players: payload.players,
            turnEndTime: payload.turnEndTime,
            gamePhase: 'Guessing' as GamePhase,
        });
        store.clearCanvas?.();
    },

    handlePlayerUpdate: ({ payload }: PlayerUpdateMsg) => {
        setStore('gameState', {
            players: payload.players,
            hostId: payload.hostId,
        });
    },

    handleTurnEnd: ({ payload }: TurnEndMsg) => {
        setStore('gameState', {
            players: payload.players,
            turnEndTime: null,
            word: null,
            wordLength: null,
            wordChoices: null,
            currentDrawerId: null,
        });
    },

    handleDraw: ({ payload }: DrawEventMsg) => {
        setStore('gameState', 'lastDrawEvent', payload);
    },

    handleGameFinished: ({ payload }: GameFinishedMsg) => {
        setStore('gameState', {
            gamePhase: 'GameEnd' as GamePhase,
            players: payload.players,
            currentDrawerId: null,
            word: null,
            wordLength: null,
            wordChoices: null,
            turnEndTime: null,
        });
    },
};
