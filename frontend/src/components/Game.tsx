import { FC } from 'react';
import { useAppStore } from '../store';
import { GameEndScreen } from './GameEndScreen';
import { LobbyScreen } from './screens/LobbyScreen.tsx';
import { GuessingScreen } from './screens/GuessingScreen.tsx';
import { WordChoiceScreen } from './screens/WordChoiceScreen.tsx';

export const CANVAS_WIDTH = 800;
export const CANVAS_HEIGHT = 600;
export const MIN_PLAYERS = 2;

export const Game: FC = () => {
    const appState = useAppStore((s) => s.gameState.gamePhase);
    const { players } = useAppStore((s) => s.gameState);

    if (appState === 'Lobby') {
        return <LobbyScreen />;
    }

    if (appState === 'WordChoice') {
        return <WordChoiceScreen />;
    }

    if (appState === 'Guessing') {
        return <GuessingScreen />;
    }

    // doesn't exist yet
    if (appState === 'Break') {
        return null;
    }

    if (appState === 'GameEnd') {
        return <GameEndScreen players={players} />;
    }
};
