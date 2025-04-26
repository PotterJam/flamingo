import { FC } from 'react';
import { useAppStore } from '../store';
import NameInput from './NameInput';
import { Game } from './Game';

export const Flamingo: FC = () => {
    const appState = useAppStore((s) => s.appState);
    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);

    if (appState === 'enterName') {
        return <NameInput />;
    }

    if (appState === 'joining' || !localPlayerId) {
        return (
            <div className="mt-10 text-center">
                <p className="mt-2 animate-pulse text-gray-500">
                    Waiting for server info...
                </p>
            </div>
        );
    }

    return <Game />;
};
