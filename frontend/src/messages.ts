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
        totalRounds: number;
        currentRound: number;
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
          startX: number;
          startY: number;
          endX: number;
          endY: number;
      }
    | {
          eventType: 'end';
          startX: number;
          startY: number;
          endX: number;
          endY: number;
          color: string;
          lineWidth: number;
      }
    | {
          eventType: 'start';
          x: number;
          y: number;
          color: string;
          lineWidth: number;
      }
    | {
          eventType: 'fill';
          x: number;
          y: number;
          color: string;
      }
    | {
          eventType: 'clear';
      }
    | {
          eventType: 'undo';
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

export interface PlayerDrawingHistory {
    playerId: string;
    playerName: string;
    drawingSteps: DrawEvent[];
}

export interface GameFinishedMsg {
    type: 'gameFinished';
    payload: {
        gamePhase: string;
        players: Player[];
        drawingHistories: PlayerDrawingHistory[];
    };
}

export interface WordRevealMsg {
    type: 'wordReveal';
    payload: {
        word: string;
    };
}

export interface TurnHelpMsg {
    type: 'turnHelp';
    payload: {
        wordOutline: string[];
        hintType: string; // "30s", "40s", etc.
    };
}

export interface PlayerCorrectMsg {
    type: 'playerCorrect';
    payload: {
        playerId: string;
        playerName: string;
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
    | TurnHelpMsg
    | PlayerCorrectMsg
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
        roundLength: number;
    };
}

export interface ClearDrawingMsg {
    type: 'clearDrawing';
    payload: {};
}

export type SendMsg =
    | SetNameMsg
    | DrawEventMsg
    | GuessMsg
    | SendChatMsg
    | SelectRoundWordMsg
    | StartGameMsg
    | PhaseChangeAckMsg
    | ClearDrawingMsg;
