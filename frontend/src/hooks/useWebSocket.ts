import { createSignal, createEffect, onCleanup } from 'solid-js';
import { ReceivedMsg, SendMsg } from '../messages';

export const WS_ROOT = '/ws';

export function useWebSocket(url: string) {
    const [isConnected, setIsConnected] = createSignal(false);
    const [receivedMessage, setReceivedMessage] = createSignal<ReceivedMsg | null>(null);
    let ws: WebSocket | null = null;

    if (import.meta.hot) {
        const wsData = import.meta.hot.data;
        if (wsData) {
            if (!ws && wsData.ws) {
                ws = wsData.ws;
                setIsConnected(wsData.isConnected ?? false);
                setReceivedMessage(wsData.receivedMessage ?? null);
            }
        }
    }

    const connect = () => {
        if (ws) {
            console.log('[useWebSocket] Already connected or connecting.');
            return;
        }

        console.log('[useWebSocket] Attempting to connect to:', url);
        try {
            ws = new WebSocket(url);
            if (import.meta.hot) {
                import.meta.hot.data.ws = ws;
            }

            ws.onopen = () => {
                console.log('[useWebSocket] WebSocket connection established.');
                setIsConnected(true);
                if (import.meta.hot) {
                    import.meta.hot.data.isConnected = true;
                }
            };

            ws.onmessage = (event) => {
                try {
                    const message = JSON.parse(event.data);
                    console.log('[useWebSocket] Message received:', message);
                    setReceivedMessage(message);
                    if (import.meta.hot) {
                        import.meta.hot.data.receivedMessage = message;
                    }
                } catch (error) {
                    console.error(
                        '[useWebSocket] Error parsing message:',
                        error,
                        event.data
                    );
                }
            };

            ws.onerror = (error) => {
                console.error('[useWebSocket] WebSocket error:', error);
            };

            ws.onclose = (event) => {
                console.log(
                    '[useWebSocket] WebSocket connection closed:',
                    event.code,
                    event.reason,
                    'wasClean:',
                    event.wasClean
                );
                setIsConnected(false);
                if (import.meta.hot) {
                    import.meta.hot.data.isConnected = false;
                    import.meta.hot.data.ws = null;
                }
                ws = null;
            };
        } catch (error) {
            console.error(
                '!!! CRITICAL ERROR: Failed to create WebSocket:',
                error
            );
            setIsConnected(false);
            if (import.meta.hot) {
                import.meta.hot.data.isConnected = false;
                import.meta.hot.data.ws = null;
            }
            ws = null;
        }
    };

    const disconnect = () => {
        if (ws && ws.readyState === WebSocket.OPEN) {
            console.log('[useWebSocket] Closing WebSocket connection.');
            ws.close();
        }
        setIsConnected(false);
        if (import.meta.hot) {
            import.meta.hot.data.isConnected = false;
            import.meta.hot.data.ws = null;
        }
        ws = null;
    };

    const sendMessage = (message: SendMsg) => {
        console.log('[useWebSocket] sendMessage called with:', message);
        console.log('[useWebSocket] WebSocket state:', ws?.readyState);
        console.log('[useWebSocket] WebSocket OPEN constant:', WebSocket.OPEN);
        
        if (ws && ws.readyState === WebSocket.OPEN) {
            try {
                const msg = JSON.stringify(message);
                console.log('[useWebSocket] Sending message:', message);
                console.log('[useWebSocket] Stringified message:', msg);
                ws.send(msg);
                console.log('[useWebSocket] Message sent successfully');
            } catch (error) {
                console.error(
                    '[useWebSocket] Error stringifying message:',
                    error
                );
            }
        } else {
            console.error(
                '[useWebSocket] WebSocket not connected. Cannot send. ReadyState:',
                ws?.readyState
            );
        }
    };

    createEffect(() => {
        if (!ws) {
            connect();
        }
    });

    onCleanup(() => {
        if (!import.meta.hot) {
            disconnect();
        }
    });

    return { isConnected, sendMessage, receivedMessage };
}
