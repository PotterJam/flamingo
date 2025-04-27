import { useState, useEffect, useRef, useCallback } from 'react';
import { ReceivedMsg, SendMsg } from '../messages';

export const WS_ROOT = 'ws://localhost:8080/ws';

export function useWebSocket(url: string) {
    const [isConnected, setIsConnected] = useState(false);
    const [receivedMessage, setReceivedMessage] = useState<ReceivedMsg | null>(
        null
    );
    const ws = useRef<WebSocket>(null);

    const connect = useCallback(() => {
        if (
            ws.current &&
            (ws.current.readyState === WebSocket.OPEN ||
                ws.current.readyState === WebSocket.CONNECTING)
        ) {
            console.log('[useWebSocket] Already connected or connecting.');
            return;
        }

        console.log('[useWebSocket] Attempting to connect to:', url);
        try {
            ws.current = new WebSocket(url);

            ws.current.onopen = () => {
                console.log('[useWebSocket] WebSocket connection established.');
                setIsConnected(true);
            };

            ws.current.onmessage = (event) => {
                try {
                    const message = JSON.parse(event.data);
                    console.log('[useWebSocket] Message received:', message);
                    setReceivedMessage(message);
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
                ws.current = null;
            };
        } catch (error) {
            console.error(
                '!!! CRITICAL ERROR: Failed to create WebSocket:',
                error
            );
            setIsConnected(false);
            ws.current = null;
        }
    }, []);

    const disconnect = useCallback(() => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            console.log('[useWebSocket] Closing WebSocket connection.');
            ws.current.close();
        }
        setIsConnected(false);
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
        connect();
        return () => {
            disconnect();
        };
    }, [connect, disconnect]);

    return { isConnected, sendMessage, receivedMessage };
}
