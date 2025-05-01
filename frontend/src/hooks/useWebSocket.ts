import { useState, useEffect, useRef, useCallback } from 'react';
import { ReceivedMsg, SendMsg } from '../messages';

export const WS_ROOT = '/ws';

export function useWebSocket(url: string) {
    const [isConnected, setIsConnected] = useState(false);
    const [receivedMessage, setReceivedMessage] = useState<ReceivedMsg | null>(null);
    const ws = useRef<WebSocket | null>(null);

    // Initialize from HMR data if available
    if (import.meta.hot) {
        const wsData = import.meta.hot.data;
        if (wsData) {
            if (!ws.current && wsData.ws) {
                ws.current = wsData.ws;
                setIsConnected(wsData.isConnected ?? false);
                setReceivedMessage(wsData.receivedMessage ?? null);
            }
        }
    }

    const connect = useCallback(() => {
        if (ws.current) {
            console.log('[useWebSocket] Already connected or connecting.');
            return;
        }

        console.log('[useWebSocket] Attempting to connect to:', url);
        try {
            ws.current = new WebSocket(url);
            if (import.meta.hot) {
                import.meta.hot.data.ws = ws.current;
            }

            ws.current.onopen = () => {
                console.log('[useWebSocket] WebSocket connection established.');
                setIsConnected(true);
                if (import.meta.hot) {
                    import.meta.hot.data.isConnected = true;
                }
            };

            ws.current.onmessage = (event) => {
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

            ws.current.onerror = (error) => {
                console.error('[useWebSocket] WebSocket error:', error);
            };

            ws.current.onclose = (event) => {
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
                ws.current = null;
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
            ws.current = null;
        }
    }, [url]);

    const disconnect = useCallback(() => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            console.log('[useWebSocket] Closing WebSocket connection.');
            ws.current.close();
        }
        setIsConnected(false);
        if (import.meta.hot) {
            import.meta.hot.data.isConnected = false;
            import.meta.hot.data.ws = null;
        }
        ws.current = null;
    }, []);

    const sendMessage = useCallback((message: SendMsg) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            try {
                const msg = JSON.stringify(message);
                console.log('[useWebSocket] Sending message:', message);
                ws.current.send(msg);
            } catch (error) {
                console.error(
                    '[useWebSocket] Error stringifying message:',
                    error
                );
            }
        } else {
            console.error(
                '[useWebSocket] WebSocket not connected. Cannot send. ReadyState:',
                ws.current?.readyState
            );
        }
    }, []);

    useEffect(() => {
        // Only connect if we don't already have a connection
        if (!ws.current) {
            connect();
        }
        return () => {
            // Only disconnect if this is a full unmount, not an HMR
            if (!import.meta.hot) {
                disconnect();
            }
        };
    }, [connect, disconnect]);

    return { isConnected, sendMessage, receivedMessage };
}
