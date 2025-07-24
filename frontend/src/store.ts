import { createStore, produce } from 'solid-js/store';
import { createEffect } from 'solid-js';
import {
    ChatMessage,
    DrawEvent,
    DrawEventMsg,
    GameInfoMsg,
    Player,
    PlayerScoreGain,
    PlayerUpdateMsg,
    ReceivedMsg,
    RoundScoreDisplayMsg,
    SendMsg,
    TurnEndMsg,
    TurnHelpMsg,
    TurnSetupMsg,
    TurnStartMsg,
    GameFinishedMsg,
    WordRevealMsg,
    CanvasUpdateMsg,
} from './messages';
import { GamePhase, Path, PathPoint } from './model';

// Map backend phase names to frontend phase names
const mapBackendPhaseToFrontend = (backendPhase: string): GamePhase => {
    switch (backendPhase) {
        case 'WaitingInLobby':
            return 'Lobby';
        case 'RoundSetup':
            return 'WordChoice';
        case 'RoundInProgress':
            return 'Guessing';
        case 'RoundScoreDisplay':
            return 'ScoreDisplay';
        case 'RoundFinished':
            return 'Guessing'; // Keep showing guessing screen during the brief results phase
        case 'GameOver':
            return 'GameEnd';
        default:
            console.warn(
                `Unknown backend phase: ${backendPhase}, defaulting to Lobby`
            );
            return 'Lobby';
    }
};

export interface WhiteboardState {
    finishedPaths: Path[];
    currentPath: PathPoint[];
}

export interface GameState {
    gamePhase: GamePhase;
    players: Player[];
    currentDrawerId: string | null;
    hostId: string | null;
    localPlayerId: string | null;
    word: string | null;
    wordOutline: string[] | null;
    wordChoices: string[] | null;
    messages: ChatMessage[];
    turnEndTime: number | null;
    lastDrawEvent: DrawEvent | null;
    scoreDisplay: {
        correctWord: string;
        scoreGains: PlayerScoreGain[];
    } | null;
    totalRounds: number | null;
    currentRound: number | null;
}

const initialWhiteboardState: WhiteboardState = {
    finishedPaths: [],
    currentPath: [],
};

const initialGameState: GameState = {
    gamePhase: 'Lobby',
    players: [],
    currentDrawerId: null,
    hostId: null,
    localPlayerId: null,
    word: null,
    wordChoices: null,
    wordOutline: null,
    messages: [],
    turnEndTime: null,
    lastDrawEvent: null,
    scoreDisplay: null,
    totalRounds: null,
    currentRound: null,
};

export interface AppState {
    sendMessage: (message: SendMsg) => void;
    lastMessage: ReceivedMsg | null;
    selfName: string;
    selfId: string;
    launchAsHost: boolean;
    gameState: GameState;
    whiteboardState: WhiteboardState;
    roomId: string | null;
    clearCanvas: (() => void) | null;

    roundCount: number;
    roundLength: number;
}

const initialAppState: AppState = {
    sendMessage: (_) => {
        throw new Error('sending message without sender configured');
    },
    lastMessage: null,
    selfName: '',
    selfId: '',
    launchAsHost: false,
    gameState: initialGameState,
    whiteboardState: initialWhiteboardState,
    roomId: null,
    clearCanvas: null,
    roundCount: 3,
    roundLength: 45,
};

const getStoredState = (): Partial<AppState> => {
    try {
        const stored = sessionStorage.getItem('flamingo-store');
        if (stored) {
            const parsed = JSON.parse(stored);
            // Don't restore sendMessage from session storage as it should be assigned dynamically
            const { sendMessage, ...rest } = parsed;
            return rest;
        }
        return {};
    } catch {
        return {};
    }
};

export const [store, setStore] = createStore<AppState>({
    ...initialAppState,
    ...getStoredState(),
});

createEffect(() => {
    // Don't save sendMessage to session storage as it should be assigned dynamically
    const { sendMessage, ...storeWithoutSendMessage } = store;
    sessionStorage.setItem(
        'flamingo-store',
        JSON.stringify(storeWithoutSendMessage)
    );
});

export const actions = {
    assignSendMessage: (func: (message: SendMsg) => void) => {
        setStore(
            produce((state) => {
                state.sendMessage = func;
            })
        );
    },

    setLastMessage: (message: ReceivedMsg) => {
        setStore(
            produce((state) => {
                state.lastMessage = message;
            })
        );
    },

    setState: (newState: GamePhase) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = newState;
            })
        );
    },

    nameChosen: (name: string) => {
        setStore(
            produce((state) => {
                state.selfName = name;
            })
        );
    },

    roomCreated: (room: string) => {
        setStore(
            produce((state) => {
                state.roomId = room;
                state.launchAsHost = true;
            })
        );
    },

    joinRoom: (roomId: string) => {
        setStore(
            produce((state) => {
                state.roomId = roomId;
                state.launchAsHost = false;
            })
        );
    },

    resetGameState: () => {
        setStore(
            produce((state) => {
                state.gameState = initialGameState;
            })
        );
    },

    addChatMessage: (message: ChatMessage) => {
        setStore(
            produce((state) => {
                state.gameState.messages.push(message);
            })
        );
    },

    setClearCanvas: (callback: (() => void) | null) => {
        setStore(
            produce((state) => {
                state.clearCanvas = callback;
            })
        );
    },

    setRoundCount: (count: number) => {
        setStore(
            produce((state) => {
                state.roundCount = count;
            })
        );
    },

    setRoundLength: (length: number) => {
        setStore(
            produce((state) => {
                state.roundLength = length;
            })
        );
    },

    handleGameInfo: ({ payload }: GameInfoMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.localPlayerId = payload.yourId;
                state.gameState.players = payload.players;
                state.gameState.hostId = payload.hostId;
                if (payload.currentDrawerId) {
                    state.gameState.currentDrawerId = payload.currentDrawerId;
                }
                if (payload.turnEndTime) {
                    state.gameState.turnEndTime = payload.turnEndTime;
                }
                state.gameState.currentDrawerId =
                    payload.currentDrawerId ?? null;
                state.gameState.wordOutline = payload.wordOutline ?? null;
                state.gameState.turnEndTime = payload.turnEndTime ?? null;
            })
        );
    },

    handleTurnSetup: ({ payload }: TurnSetupMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.currentDrawerId = payload.currentDrawerId;
                state.gameState.wordChoices = payload.wordChoices ?? null;
                state.gameState.players = payload.players;
                state.gameState.turnEndTime = payload.turnEndTime;
            })
        );
    },

    handleTurnStart: ({ payload }: TurnStartMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.wordChoices = null;
                state.gameState.currentDrawerId = payload.currentDrawerId;
                state.gameState.word = payload.word ?? null;
                state.gameState.wordOutline = payload.wordOutline ?? null;
                state.gameState.players = payload.players;
                state.gameState.turnEndTime = payload.turnEndTime;
                state.gameState.scoreDisplay = null;
                state.gameState.totalRounds = payload.totalRounds;
                state.gameState.currentRound = payload.currentRound;
                state.whiteboardState = initialWhiteboardState;
            })
        );
        store.clearCanvas?.();
    },

    handlePlayerUpdate: ({ payload }: PlayerUpdateMsg) => {
        setStore(
            produce((state) => {
                state.gameState.players = payload.players;
                state.gameState.hostId = payload.hostId;
            })
        );
    },

    handleTurnEnd: ({ payload }: TurnEndMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.players = payload.players;
                state.gameState.turnEndTime = null;
                state.gameState.word = null;
                state.gameState.wordOutline = null;
                state.gameState.wordChoices = null;
                state.gameState.currentDrawerId = null;
            })
        );
    },

    handleDraw: ({ payload }: DrawEventMsg) => {
        setStore(
            produce((state) => {
                state.gameState.lastDrawEvent = payload;
            })
        );
    },

    handleRoundScoreDisplay: ({ payload }: RoundScoreDisplayMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.scoreDisplay = {
                    correctWord: payload.correctWord,
                    scoreGains: payload.scoreGains,
                };
                state.gameState.players = payload.players;
            })
        );
    },

    handleGameFinished: ({ payload }: GameFinishedMsg) => {
        setStore(
            produce((state) => {
                state.gameState.gamePhase = mapBackendPhaseToFrontend(
                    payload.gamePhase
                );
                state.gameState.players = payload.players;
                state.gameState.currentDrawerId = null;
                state.gameState.word = null;
                state.gameState.wordOutline = null;
                state.gameState.wordChoices = null;
                state.gameState.turnEndTime = null;
                state.gameState.scoreDisplay = null;
            })
        );
    },

    handleTurnHelp: ({ payload }: TurnHelpMsg) => {
        setStore(
            produce((state) => {
                state.gameState.wordOutline = payload.wordOutline;
            })
        );
    },

    handleWordReveal: ({ payload }: WordRevealMsg) => {
        setStore(
            produce((state) => {
                state.gameState.word = payload.word;
            })
        );
    },

    handleCanvasUpdate: ({ payload }: CanvasUpdateMsg) => {
        // TODO
    },

    startPath: (point: PathPoint) => {
        setStore(
            produce((state) => {
                state.whiteboardState.currentPath = [point];
            })
        );
    },

    continuePath: (point: PathPoint) => {
        setStore(
            produce((state) => {
                state.whiteboardState.currentPath.push(point);
            })
        );
    },

    finishPath: (colour: string, thickness: number) => {
        setStore(
            produce((state) => {
                if (state.whiteboardState.currentPath.length > 0) {
                    state.whiteboardState.finishedPaths.push({
                        points: state.whiteboardState.currentPath,
                        colour,
                        thickness,
                    });
                    state.whiteboardState.currentPath = [];
                }
            })
        );
    },
};
