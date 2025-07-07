import { Switch, Match } from 'solid-js';
import { LobbyScreen } from './screens/LobbyScreen';
import { GuessingScreen } from './screens/GuessingScreen';
import { WordChoiceScreen } from './screens/WordChoiceScreen';
import { ScoreDisplayScreen } from './screens/ScoreDisplayScreen';
import { GameEndScreen } from './screens/GameEndScreen';
import { store } from '../store';

export const CANVAS_WIDTH = 800;
export const CANVAS_HEIGHT = 600;
export const MIN_PLAYERS = 2;

export const Game = () => {
    return (
        <Switch>
            <Match when={store.gameState.gamePhase === 'Lobby'}>
                <LobbyScreen />
            </Match>
            <Match when={store.gameState.gamePhase === 'WordChoice'}>
                <WordChoiceScreen />
            </Match>
            <Match when={store.gameState.gamePhase === 'Guessing'}>
                <GuessingScreen />
            </Match>
            <Match when={store.gameState.gamePhase === 'ScoreDisplay'}>
                <ScoreDisplayScreen />
            </Match>
            <Match when={store.gameState.gamePhase === 'GameEnd'}>
                <GameEndScreen />
            </Match>
        </Switch>
    );
};
