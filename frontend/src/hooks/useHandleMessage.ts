import { createEffect, Accessor } from 'solid-js';
import { ReceivedMsg } from '../messages';
import { actions, store } from '../store';
import { soundManager } from '../sound-manager';

export const useHandleMessage = (message: Accessor<ReceivedMsg | null>) => {
    createEffect(() => {
        const msg = message();
        if (msg) {
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
                    soundManager.startOrContinueMusic();
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
                    actions.handleDrawPayload(msg);
                    break;
                }
                case 'turnEnd': {
                    actions.handleTurnEnd(msg);
                    break;
                }
                case 'roundScoreDisplay': {
                    soundManager.stopCountdown();
                    actions.handleRoundScoreDisplay(msg);
                    break;
                }
                case 'gameFinished': {
                    soundManager.stopMusic();
                    soundManager.stopCountdown();
                    actions.handleGameFinished(msg);
                    break;
                }
                case 'wordReveal': {
                    soundManager.playSound('correctGuess');
                    actions.handleWordReveal(msg);
                    break;
                }
                case 'playerCorrect': {
                    soundManager.playSound('otherPlayerCorrect');
                    break;
                }
                case 'turnHelp': {
                    actions.handleTurnHelp(msg);
                    break;
                }
                case 'phaseChangeAck': {
                    store.sendMessage(msg);
                    break;
                }
                case 'canvasUpdate': {
                    actions.handleCanvasUpdate(msg);
                    break;
                }
                case 'rasterUpdate': {
                    actions.handleRasterUpdate(msg);
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
