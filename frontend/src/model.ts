export type GamePhase =
    | 'Lobby'
    | 'WordChoice'
    | 'Guessing'
    | 'ScoreDisplay'
    | 'GameEnd';

// The format perfect-freehand expects: [x, y, pressure]
export type PathPoint = [number, number, number];

export interface Path {
    points: PathPoint[];
    thickness: number;
    colour: string;
}

export interface Point {
    x: number;
    y: number;
}
