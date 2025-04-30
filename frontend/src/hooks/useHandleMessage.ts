import { ReceivedMsg } from '../messages';
import { useAppStore } from '../store';

export const useHandleMessage = (message: ReceivedMsg | null) => {
    const handleGameInfo = useAppStore((s) => s.handleGameInfo);
    const handleTurnStart = useAppStore((s) => s.handleTurnStart);
    const handleTurnSetup = useAppStore((s) => s.handleTurnSetup);

    const handlePlayerUpdate = useAppStore((s) => s.handlePlayerUpdate);
    const handleTurnEnd = useAppStore((s) => s.handleTurnEnd);
    const handleDraw = useAppStore((s) => s.handleDraw);
    const addChatMessage = useAppStore((s) => s.addChatMessage);

    if (message) {
        console.log('Processing message in useEffect:', message);

        switch (message.type) {
            case 'gameInfo': {
                handleGameInfo(message);
                break;
            }
            case 'playerUpdate': {
                handlePlayerUpdate(message);
                break;
            }
            case 'turnSetup':
                handleTurnSetup(message);
                break;
            case 'turnStart': {
                handleTurnStart(message);
                break;
            }
            case 'chat': {
                addChatMessage(message.payload);
                break;
            }
            case 'drawEvent': {
                handleDraw(message);
                break;
            }
            case 'turnEnd': {
                handleTurnEnd(message);
                break;
            }
            case 'error': {
                const payload = message.payload;
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
                console.warn('Received unknown message: ', message);
        }
    }
};
