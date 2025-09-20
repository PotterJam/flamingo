import { createEffect, Show } from 'solid-js';
import { actions, setSendMessageFn, store } from '../store';
import { Game } from './Game';
import { useHandleMessage } from '../hooks/useHandleMessage';
import { useWebSocket } from '../hooks/useWebSocket';

interface FlamingoProps {
    wsUrl: string;
}

export const Flamingo = (props: FlamingoProps) => {
    const { isConnected, receivedMessage, sendMessage } = useWebSocket(
        props.wsUrl
    );
    useHandleMessage(receivedMessage);

    createEffect(() => {
        setSendMessageFn(sendMessage);
    });

    createEffect(() => {
        if (!isConnected()) {
            actions.resetGameState();
        }
    });

    return (
        <Show
            when={isConnected()}
            fallback={<div class="mt-10 text-center">Loading...</div>}
        >
            <Show
                when={store.gameState.localPlayerId}
                fallback={
                    <div class="mt-10 text-center">
                        <p class="mt-2 animate-pulse text-gray-500">
                            Waiting for server info...
                        </p>
                    </div>
                }
            >
                <Game />
            </Show>
        </Show>
    );
};
