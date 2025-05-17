export interface Player {
    id: string;
    name: string;
    score: number;
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

export interface GuessMsg {
    type: 'guess';
    payload: {
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        wordChoices?: string[]; // undefined for guessing players
    };
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

export interface GuessLetter {
    index: number;
    letter: string;
}

export interface TurnStartMsg {
    type: 'turnStart';
    payload: {
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        word?: string; // undefined for guessing players
        wordLength: number;
        preFilledLetters: GuessLetter[];
    };
}

export interface TurnEndMsg {
    type: 'turnEnd';
    payload: {
        correctWord: string;
        players: Player[];
        roundScores: { [playerId: string]: number };
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

export interface GameFinishedMsg {
    type: 'gameFinished';
    payload: {
        players: Player[];
    };
}

export interface CorrectGuessMsg {
    type: 'guess';
    payload: {
        playerId: string;
        playerScoreDelta: number;
    };
}

export interface GuessHelperMsg {
    type: 'guessHelper';
    payload: GuessLetter;
}

export type ReceivedMsg =
    | GameInfoMsg
    | PlayerUpdateMsg
    | ChatMsg
    | TurnSetupMsg
    | TurnStartMsg
    | TurnEndMsg
    | DrawEventMsg
    | ErrorMsg
    | GameFinishedMsg
    | PhaseChangeAckMsg
    | CorrectGuessMsg
    | GuessHelperMsg;

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

export interface PhaseChangeAckMsg {
    type: 'phaseChangeAck';
    payload: {
        newPhase: string;
    };
}

export interface StartGameMsg {
    type: 'startGame';
    payload: null;
}

export type SendMsg =
    | SetNameMsg
    | DrawEventMsg
    | GuessMsg
    | SelectRoundWordMsg
    | StartGameMsg
    | PhaseChangeAckMsg;
