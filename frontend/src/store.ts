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
    GameFinishedMsg, CorrectGuessMsg, GuessHelperMsg,
} from './messages';
import { immer } from 'zustand/middleware/immer';
import { createJSONStorage, persist } from 'zustand/middleware';
import { GamePhase } from './model';

interface CorrectPlayerGuess {
    playerId: string;
    playerScoreDelta: number;
}

export interface GameState {
    guesses: CorrectPlayerGuess[];
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

export interface Room {
    roomId: string;
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
    guesses: []
};

export type AppState = {
    sendMessage: (message: SendMsg) => void;
    lastMessage: ReceivedMsg | null;

    selfName: string;
    selfId: string;
    launchAsHost: boolean;

    gameState: GameState;
    roomId: string | null;

    clearCanvas: (() => void) | null;
};

export type AppActions = {
    assignSendMessage: (func: (message: SendMsg) => void) => void;
    setLastMessage: (message: ReceivedMsg) => void;

    setState: (newState: GamePhase) => void;

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
    handleCorrectGuess: (msg: CorrectGuessMsg) => void;
    handleGuessHelper: (msg: GuessHelperMsg) => void;
};

export const useAppStore = create<AppState & AppActions & MessageHandlers>()(
    persist(
        immer((set) => ({
            gameState: initialGameState,
            roomId: null,
            gamePhase: 'connecting',
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
            handleGameInfo: ({ payload: { currentDrawerId, hostId, players, turnEndTime, yourId } }) =>
                set((s) => {
                    s.gameState.localPlayerId = yourId;
                    s.gameState.players = players;
                    s.gameState.hostId = hostId;
                    if (currentDrawerId)
                        s.gameState.currentDrawerId = currentDrawerId;
                    if (turnEndTime)
                        s.gameState.turnEndTime = turnEndTime;
                }),
            handleTurnSetup: ({ payload: { currentDrawerId, players, turnEndTime, wordChoices } }) =>
                set((s) => {
                    s.gameState.currentDrawerId = currentDrawerId;
                    s.gameState.wordChoices = wordChoices ?? null;
                    s.gameState.players = players;
                    s.gameState.turnEndTime = turnEndTime;

                    s.gameState.gamePhase = 'WordChoice';
                }),
            handleTurnStart: ({ payload: { currentDrawerId, players, turnEndTime, word, wordLength} }) =>
                set((s) => {
                    s.gameState.wordChoices = null; // The word has been chosen
                    s.gameState.guesses = [];

                    s.gameState.currentDrawerId = currentDrawerId;
                    s.gameState.word = word ?? null;
                    s.gameState.wordLength = wordLength ?? null;
                    s.gameState.players = players;
                    s.gameState.turnEndTime = turnEndTime;

                    s.clearCanvas && s.clearCanvas();

                    s.gameState.gamePhase = 'Guessing';
                }),
            handlePlayerUpdate: ({ payload: { hostId, players } }) =>
                set((s) => {
                    s.gameState.players = players;
                    s.gameState.hostId = hostId;
                }),
            handleTurnEnd: ({ payload: { players } }) =>
                set((s) => {
                    s.gameState.players = players;
                    s.gameState.turnEndTime = null;
                    s.gameState.word = null;
                    s.gameState.wordLength = null;
                    s.gameState.wordChoices = null;
                    s.gameState.currentDrawerId = null;
                    s.gameState.guesses = [];
                }),
            handleDraw: ({ payload }) =>
                set((s) => {
                    s.gameState.lastDrawEvent = payload;
                }),
            handleGameFinished: ({ payload: { players } }) =>
                set((s) => {
                    s.gameState.gamePhase = 'GameEnd';
                    s.gameState.players = players;
                    s.gameState.currentDrawerId = null;
                    s.gameState.word = null;
                    s.gameState.wordLength = null;
                    s.gameState.wordChoices = null;
                    s.gameState.turnEndTime = null;
                    s.gameState.guesses = [];
                }),
            handleCorrectGuess: ({ payload: { playerId, playerScoreDelta, word } }) =>
                set((s) => {
                    if (s.gameState.guesses.some(g => g.playerId === playerId)) {
                        return;
                    }

                    if (word) {
                        s.gameState.word = word;
                    }

                    s.gameState.guesses.push({ playerId: playerId, playerScoreDelta: playerScoreDelta });
                }),
            handleGuessHelper: ({ payload: {index, letter} }) =>
                set((s) => {
                    // TODO
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
