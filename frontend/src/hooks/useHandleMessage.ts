import { createEffect, Accessor } from 'solid-js';
import { ReceivedMsg } from '../messages';
import { actions, useAppStore } from '../store';

export const useHandleMessage = (message: Accessor<ReceivedMsg | null>) => {
    const store = useAppStore();

    createEffect(() => {
        const msg = message();
        if (msg) {
            console.log('Processing message in createEffect:', msg);

            switch (msg.type) {
                case 'gameInfo': {
                    actions.handleGameInfo(msg);
                    break;
                }
                case 'playerUpdate': {
                    actions.handlePlayerUpdate(msg);
                    break;
                }
                case 'turnSetup':
                    actions.handleTurnSetup(msg);
                    break;
                case 'turnStart': {
                    actions.handleTurnStart(msg);
                    break;
                }
                case 'chat': {
                    actions.addChatMessage(msg.payload);
                    break;
                }
                case 'drawEvent': {
                    actions.handleDraw(msg);
                    break;
                }
                case 'turnEnd': {
                    actions.handleTurnEnd(msg);
                    break;
                }
                case 'roundScoreDisplay': {
                    actions.handleRoundScoreDisplay(msg);
                    break;
                }
                case 'gameFinished': {
                    actions.handleGameFinished(msg);
                    break;
                }
                case 'wordReveal': {
                    actions.handleWordReveal(msg);
                    break;
                }
                case 'phaseChangeAck': {
                    store.sendMessage(msg);
                    break;
                }
                case 'error': {
                    const payload = msg.payload;
                    if (!payload) {
                        console.error('Received error with null payload');
                        break;
                    }
                    actions.addChatMessage({
                        senderName: 'System',
                        message: `Error: ${payload.message || 'Unknown error'}`,
                        isSystem: true,
                    });
                    break;
                }
                default:
                    console.warn('Received unknown message: ', msg);
            }
        }
    });
};
