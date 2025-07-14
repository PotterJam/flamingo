import { Switch, Match } from 'solid-js';
import { LobbyScreen } from './screens/LobbyScreen';
import { GuessingScreen } from './screens/GuessingScreen';
import { WordChoiceScreen } from './screens/WordChoiceScreen';
import { ScoreDisplayScreen } from './screens/ScoreDisplayScreen';
import { GameEndScreen } from './screens/GameEndScreen';
import { store } from '../store';
import { FlamingoBackground } from './Background';
import { GridBackground } from './GridBackground';

export const CANVAS_WIDTH = 800;
export const CANVAS_HEIGHT = 600;
export const MIN_PLAYERS = 2;

export const Game = () => {
    return (
        <Switch>
            <Match when={store.gameState.gamePhase === 'Lobby'}>
                <GridBackground>
                    <LobbyScreen />
                </GridBackground>
            </Match>
            <Match when={store.gameState.gamePhase === 'WordChoice'}>
                <FlamingoBackground>
                    <WordChoiceScreen />
                </FlamingoBackground>
            </Match>
            <Match when={store.gameState.gamePhase === 'Guessing'}>
                <FlamingoBackground>
                    <GuessingScreen />
                </FlamingoBackground>
            </Match>
            <Match when={store.gameState.gamePhase === 'ScoreDisplay'}>
                <FlamingoBackground>
                    <ScoreDisplayScreen />
                </FlamingoBackground>
            </Match>
            <Match when={store.gameState.gamePhase === 'GameEnd'}>
                <FlamingoBackground>
                    <GameEndScreen />
                </FlamingoBackground>
            </Match>
        </Switch>
    );
};
