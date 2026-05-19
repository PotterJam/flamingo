import { createEffect, Accessor } from 'solid-js';
import { ReceivedMsg } from '../messages';
import { actions, store } from '../store';
import { soundManager } from '../sound-manager';
import { createRoundAudioLifecycle } from '../audio-lifecycle';

const roundAudioLifecycle = createRoundAudioLifecycle(soundManager);

const syncRoundAudio = () => {
    roundAudioLifecycle.sync(
        store.gameState.gamePhase,
        store.gameState.turnEndTime
    );
};

export const useHandleMessage = (message: Accessor<ReceivedMsg | null>) => {
    createEffect(() => {
        const msg = message();
        if (msg) {
            switch (msg.type) {
                case 'gameInfo': {
                    actions.handleGameInfo(msg);
                    syncRoundAudio();
                    break;
                }
                case 'playerUpdate': {
                    actions.handlePlayerUpdate(msg);
                    break;
                }
                case 'turnSetup':
                    actions.handleTurnSetup(msg);
                    syncRoundAudio();
                    break;
                case 'turnStart': {
                    actions.handleTurnStart(msg);
                    syncRoundAudio();
                    break;
                }
                case 'chat': {
                    actions.addChatMessage(msg.payload);
                    break;
                }
                case 'drawEvent': {
                    actions.handleDrawPayload(msg.payload);
                    break;
                }
                case 'turnEnd': {
                    actions.handleTurnEnd(msg);
                    syncRoundAudio();
                    break;
                }
                case 'roundScoreDisplay': {
                    actions.handleRoundScoreDisplay(msg);
                    syncRoundAudio();
                    break;
                }
                case 'gameFinished': {
                    actions.handleGameFinished(msg);
                    roundAudioLifecycle.stopAll();
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
                    actions.passThroughMessage(msg);
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
