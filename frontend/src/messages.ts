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
        gamePhase: string;
        hostId: string;
        isGameActive: boolean;
        players: Player[];
        yourId: string;
        currentDrawerId?: string;
        wordOutline?: string[];
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

export interface SendChatMsg {
    type: 'chat';
    payload: {
        message: string;
    };
}

export interface TurnSetupMsg {
    type: 'turnSetup';
    payload: {
        gamePhase: string;
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        wordChoices?: string[]; // undefined for guessing players
    };
}

export interface TurnStartMsg {
    type: 'turnStart';
    payload: {
        gamePhase: string;
        currentDrawerId: string;
        players: Player[];
        turnEndTime: number;
        word?: string; // undefined for guessing players
        wordOutline: string[];
    };
}

export interface TurnEndMsg {
    type: 'turnEnd';
    payload: {
        gamePhase: string;
        correctWord: string;
        players: Player[];
        roundScores: { [playerId: string]: number };
    };
}

export interface PlayerScoreGain {
    playerId: string;
    playerName: string;
    scoreGain: number;
}

export interface RoundScoreDisplayMsg {
    type: 'roundScoreDisplay';
    payload: {
        gamePhase: string;
        correctWord: string;
        scoreGains: PlayerScoreGain[];
        players: Player[];
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
        gamePhase: string;
        players: Player[];
    };
}

export interface WordRevealMsg {
    type: 'wordReveal';
    payload: {
        word: string;
    };
}

export type ReceivedMsg =
    | GameInfoMsg
    | PlayerUpdateMsg
    | ChatMsg
    | TurnSetupMsg
    | TurnStartMsg
    | TurnEndMsg
    | RoundScoreDisplayMsg
    | DrawEventMsg
    | ErrorMsg
    | GameFinishedMsg
    | WordRevealMsg
    | PhaseChangeAckMsg;

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

export interface GuessMsg {
    type: 'guess';
    payload: {
        guess: string;
    };
}

export interface StartGameMsg {
    type: 'startGame';
    payload: {
        roundCount: number;
    };
}

export type SendMsg =
    | SetNameMsg
    | DrawEventMsg
    | GuessMsg
    | SendChatMsg
    | SelectRoundWordMsg
    | StartGameMsg
    | PhaseChangeAckMsg;
