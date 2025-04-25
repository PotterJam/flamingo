import { FC, useEffect } from 'react';
import { ReceivedMsg } from '../messages';
import { useAppStore } from '../store';
import { Scaffolding } from './Scaffolding';
import NameInput from './NameInput';
import { Game } from './Game';

export const EventWrapper: FC<{
    isConnected: boolean;
    receivedMessage: ReceivedMsg | null;
}> = ({ isConnected, receivedMessage }) => {
    const handleGameInfo = useAppStore((s) => s.handleGameInfo);
    const handleTurnStart = useAppStore((s) => s.handleTurnStart);
    const handlePlayerUpdate = useAppStore((s) => s.handlePlayerUpdate);
    const handlePlayerGuessedCorrectly = useAppStore(
        (s) => s.handlePlayerGuessedCorrectly
    );
    const handleTurnEnd = useAppStore((s) => s.handleTurnEnd);
    const addChatMessage = useAppStore((s) => s.addChatMessage);

    const appState = useAppStore((s) => s.appState);
    const localPlayerId = useAppStore((s) => s.gameState.localPlayerId);

    useEffect(() => {
        if (receivedMessage) {
            console.log('Processing message in useEffect:', receivedMessage);

            switch (receivedMessage.type) {
                case 'gameInfo': {
                    handleGameInfo(receivedMessage);
                    break;
                }
                case 'playerUpdate': {
                    handlePlayerUpdate(receivedMessage);
                    break;
                }
                case 'turnStart': {
                    handleTurnStart(receivedMessage);
                    break;
                }
                case 'playerGuessedCorrectly': {
                    handlePlayerGuessedCorrectly(receivedMessage);
                    break;
                }
                case 'chat': {
                    addChatMessage(receivedMessage.payload);
                    break;
                }
                case 'drawEvent': {
                    break;
                }
                case 'turnEnd': {
                    handleTurnEnd(receivedMessage);
                    break;
                }
                case 'error': {
                    const payload = receivedMessage.payload;
                    if (!payload) {
                        console.error('Received error with null payload');
                        break;
                    }
                    addChatMessage({
                        senderName: 'System',
                        message: `Error: ${payload.message || 'Unknown error'}`,
                        isSystem: true,
                    });
                    break;
                }
                default:
                    console.warn('Received unknown message: ', receivedMessage);
            }
        }
    }, [receivedMessage, appState]);

    if (appState === 'enterName') {
        return (
            <Scaffolding>
                <NameInput />
            </Scaffolding>
        );
    }

    if (!isConnected) {
        return (
            <Scaffolding>
                <div className="mt-10 text-center">Loading...</div>
            </Scaffolding>
        );
    }

    if (appState === 'joining' || !localPlayerId) {
        return (
            <Scaffolding>
                <div className="mt-10 text-center">
                    <p className="mt-2 animate-pulse text-gray-500">
                        Waiting for server info...
                    </p>
                </div>
            </Scaffolding>
        );
    }

    return (
        <Scaffolding>
            <Game />
        </Scaffolding>
    );
};
