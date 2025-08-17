export type GamePhase =
    | 'Lobby'
    | 'WordChoice'
    | 'Guessing'
    | 'ScoreDisplay'
    | 'GameEnd';

export interface Point {
    x: number;
    y: number;
}
