import { createStore, produce } from 'solid-js/store';
import { createEffect } from 'solid-js';
import {
    ChatMessage,
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
    DrawEvent,
} from './messages';
import { GamePhase } from './model';

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
    scoreDisplay: {
        correctWord: string;
        scoreGains: PlayerScoreGain[];
    } | null;
    totalRounds: number | null;
    currentRound: number | null;

    pendingDrawEvent: DrawEvent | null;
    drawEventsStack: DrawEvent[];
}

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
    scoreDisplay: null,
    totalRounds: null,
    currentRound: null,
    pendingDrawEvent: null,
    drawEventsStack: [],
};

export interface AppState {
    lastMessage: ReceivedMsg | null;
    selfName: string;
    selfId: string;
    launchAsHost: boolean;
    gameState: GameState;
    roomId: string | null;

    roundCount: number;
    roundLength: number;
}

const initialAppState: AppState = {
    lastMessage: null,
    selfName: '',
    selfId: '',
    launchAsHost: false,
    gameState: initialGameState,
    roomId: null,
    roundCount: 3,
    roundLength: 45,
};

const getStoredState = (): Partial<AppState> => {
    const stored = sessionStorage.getItem('flamingo-store');
    if (stored) {
        return JSON.parse(stored);
    }
    return {};
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
let websocketSend: (message: SendMsg) => void = () => {
    throw new Error('Send message must be set to send websocket events');
};

export const setSendMessageFn = (sendMessage:((message: SendMsg) => void)) => {
    websocketSend = sendMessage;
}

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
            })
        );
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
                state.gameState.drawEventsStack = [];
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

    handleClientDraw: (message: DrawEvent) => {
        actions.manageStackEvent(message);
        store.sendMessage({
            type: 'drawEvent',
            payload: message,
        });
    },

    handleDrawPayload: (message: DrawEvent) => {
        actions.manageStackEvent(message);
        setStore(
            produce((state) => {
                state.gameState.pendingDrawEvent = message;
            })
        );
    },

    clearPendingDrawEvent: () => {
        setStore(
            produce((state) => {
                state.gameState.pendingDrawEvent = null;
            })
        );
    },

    manageStackEvent: (event: DrawEvent) => {
        if (event.eventType !== 'undo') {
            setStore(
                produce((state) => {
                    state.gameState.drawEventsStack.push(event);
                })
            );
            return;
        }

        setStore(
            produce((state) => {
                const stack = state.gameState.drawEventsStack;
                const lastFullAction = stack.findLast(
                    (event) =>
                        event.eventType === 'fill' ||
                        event.eventType === 'start' ||
                        event.eventType === 'clear'
                );
                if (lastFullAction) {
                    const lastActionIndex = stack.lastIndexOf(lastFullAction);
                    stack.splice(lastActionIndex);
                }
            })
        );
    },
};
