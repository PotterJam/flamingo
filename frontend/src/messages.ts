export interface Player {
    id: string;
    name: string;
    isHost?: boolean;
    hasGuessedCorrectly?: boolean;
}

export interface LoginMsg {
    type: 'login';
    payload: { playerName: string; roomId: string; isHost: boolean };
}

export interface GameInfoMsg {
    type: 'gameInfo';
    payload: {
        hostId: string;
        isGameActive: boolean;
        players: Player[];
        yourId: string;
        currentDrawerId?: string;
        wordLength?: number;
        word?: string;
        turnEndTime?: number;
    };
}

export interface PlayerUpdateMsg {
    type: 'playerUpdate';
    payload: {
        players: Player[];
        hostId: string;
    };
}

export interface ChatMessage {
    senderName: string;
    message: string;
    isSystem: boolean;
}

export interface ChatMsg {
    type: 'chat';
    payload: ChatMessage;
}

export interface TurnSetupMsg {
    type: 'turnSetup';
    payload: {
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        wordChoices?: string[]; // undefined for guessing players
    };
}


export interface TurnStartMsg {
    type: 'turnStart';
    payload: {
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        word?: string; // undefined for guessing players
        wordLength: number;
    };
}

export interface TurnEndMsg {
    type: 'turnEnd';
    payload: {
        correctWord: string;
    };
}

export interface PlayerGuessedCorrectlyMsg {
    type: 'playerGuessedCorrectly';
    payload: {
        playerId: string;
    };
}

export type DrawEvent =
    | {
          color: string;
          eventType: 'draw';
          lineWidth: number;
          x: number;
          y: number;
      }
    | {
          eventType: 'end';
      }
    | {
          eventType: 'start';
          x: number;
          y: number;
          color: string;
          lineWidth: number;
      };

export interface DrawEventMsg {
    type: 'drawEvent';
    payload: DrawEvent;
}

export interface ErrorMsg {
    type: 'error';
    payload?: {
        message: string;
    };
}

export type ReceivedMsg =
    | GameInfoMsg
    | PlayerUpdateMsg
    | ChatMsg
    | TurnSetupMsg
    | TurnStartMsg
    | TurnEndMsg
    | PlayerGuessedCorrectlyMsg
    | DrawEventMsg
    | ErrorMsg;

export interface SetNameMsg {
    type: 'setName';
    payload: {
        name: string;
    };
}

export interface SelectRoundWordMsg {
    type: 'selectRoundWord';
    payload: {
        word: string;
    };
}

export interface GuessMsg {
    type: 'guess';
    payload: {
        guess: string;
    };
}

export interface StartGameMsg {
    type: 'startGame';
    payload: null;
}

export type SendMsg = SetNameMsg | DrawEventMsg | GuessMsg | SelectRoundWordMsg | StartGameMsg;
