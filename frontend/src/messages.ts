export interface Player {
    id: string;
    hasGuessedCorrectly?: boolean;
    isHost?: boolean;
    name: string;
}

export interface GameInfoMsg {
    type: 'gameInfo',
    payload: {
        hostId: string,
        isGameActive: boolean,
        players: Player[],
        yourId: string,
        currentDrawerId?: string,
        wordLength?: number,
        word?: string,
        turnEndTime?: number,
    },
}

export interface PlayerUpdateMsg {
    type: 'playerUpdate',
    payload: {
        players: Player[],
        hostId: string,
    },
}

export interface ChatMessage {
    senderName: string;
    message: string;
    isSystem: boolean;
}

export interface ChatMsg {
    type: 'chat',
    payload: ChatMessage,
}

export interface TurnStartMsg {
    type: 'turnStart',
    payload: {
        currentDrawerId: string,
        players: Player[],
        turnEndTime: number,
        word?: string, // undefined for guessing players
        wordLength: number,
    },
}

export interface TurnEndMsg {
    type: 'turnEnd',
    payload: {
        correctWord: string,
    },
}

export interface PlayerGuessedCorrectlyMsg {
    type: 'playerGuessedCorrectly',
    payload: {
        playerId: string,
    },
}

export interface DrawEventMsg {
    type: 'drawEvent',
    payload: {
        color: string,
        eventType: 'draw',
        lineWidth: number,
        x: number,
        y: number,
    } | {
        eventType: 'end',
    },
}

export interface ErrorMsg {
    type: 'error',
    payload?: {
        message: string,
    },
}

export type ReceivedMsg = GameInfoMsg | PlayerUpdateMsg | ChatMsg | TurnStartMsg | TurnEndMsg | PlayerGuessedCorrectlyMsg | DrawEventMsg | ErrorMsg;

export interface SetNameMsg {
    type: 'setName',
    payload: {
        name: string,
    },
}

export interface GuessMsg {
    type: 'guess',
    payload: {
        guess: string,
    }
}

export interface StartGameMsg {
    type: 'startGame',
    payload: null,
}

export type SendMsg = SetNameMsg | DrawEventMsg | GuessMsg | StartGameMsg;
