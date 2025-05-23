import { FC, useEffect } from 'react';
import { useAppStore } from '../store';
import { Game } from './Game';
import { useHandleMessage } from '../hooks/useHandleMessage';
import { useWebSocket } from '../hooks/useWebSocket';

interface FlamingoProps {
    wsUrl: string;
}

export const Flamingo: FC<FlamingoProps> = ({ wsUrl }) => {
    const { isConnected, receivedMessage, sendMessage } = useWebSocket(wsUrl);
    useHandleMessage(receivedMessage);

    const assignSendMessage = useAppStore((s) => s.assignSendMessage);
    useEffect(() => {
        assignSendMessage(sendMessage);
    }, [sendMessage]);

    const appState = useAppStore((state) => state.gameState.gamePhase);
    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);
    const resetGameState = useAppStore((s) => s.resetGameState);

    useEffect(() => {
        if (!isConnected) {
            console.log('WebSocket disconnected.');
            resetGameState();
        }
    }, [isConnected, appState]);
    if (!isConnected) {
        return <div className="mt-10 text-center">Loading...</div>;
    }

    if (!localPlayerId) {
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
