import { useState, useEffect, useRef, useCallback } from 'react';

const WS_URL = 'ws://localhost:8080/ws'; // Adjust if needed

export interface Player {
    id: string;
    hasGuessedCorrectly?: boolean;
    isHost: boolean;
    name: string;
}

export interface JankPayload {
    yourId: string;
    playerId: string;
    players: Player[];
    hostId: string;
    currentDrawerId: string;
    wordLength: number;
    turnEndTime: number;
    isGameActive: boolean;
    word: string | null;
}

export interface TurnEndPayload {
	correctWord: string;
}

export interface ErrorPayload {
	message: string;
}

export interface WebhookMessage {
    type: string;
    payload: JankPayload;
}

export function useWebSocket() {
    const [isConnected, setIsConnected] = useState(false);
    const [lastMessage, setLastMessage] = useState<WebhookMessage | null>(null);
    const ws = useRef<WebSocket>(null); // Ref to hold the WebSocket instance

    const connect = useCallback(() => {
        // Avoid reconnecting if already connected or connecting
        if (ws.current && (ws.current.readyState === WebSocket.OPEN || ws.current.readyState === WebSocket.CONNECTING)) {
            console.log('[useWebSocket] Already connected or connecting.');
            return;
        }

        console.log('[useWebSocket] Attempting to connect to:', WS_URL);
        try {
            ws.current = new WebSocket(WS_URL);

            ws.current.onopen = () => {
                console.log('[useWebSocket] WebSocket connection established.');
                setIsConnected(true);
            };

            ws.current.onmessage = (event) => {
                try {
                    const message = JSON.parse(event.data);
                    console.log('[useWebSocket] Message received:', message);
                    setLastMessage(message); // Update state with the new message
                } catch (error) {
                    console.error('[useWebSocket] Error parsing message:', error, event.data);
                }
            };

            ws.current.onerror = (error) => {
                console.error('[useWebSocket] WebSocket error:', error);
                // onerror often precedes onclose, connection state is handled in onclose
            };

            ws.current.onclose = (event) => {
                console.log('[useWebSocket] WebSocket connection closed:', event.code, event.reason, 'wasClean:', event.wasClean);
                setIsConnected(false);
                ws.current = null; // Clear the ref
                // Optional: Implement automatic reconnection logic here
            };
        } catch (error) {
            console.error("!!! CRITICAL ERROR: Failed to create WebSocket:", error);
            setIsConnected(false);
            ws.current = null;
        }
    }, []); // Empty dependency array means this function reference doesn't change

    const disconnect = useCallback(() => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            console.log('[useWebSocket] Closing WebSocket connection.');
            ws.current.close();
        }
        // Clear state immediately
        setIsConnected(false);
        ws.current = null;
    }, []);

    const sendMessage = useCallback((type: string, payload: unknown) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            try {
                const message = JSON.stringify({ type, payload });
                console.log('[useWebSocket] Sending message:', message);
                ws.current.send(message);
            } catch (error) {
                console.error('[useWebSocket] Error stringifying message:', error);
            }
        } else {
            console.error('[useWebSocket] WebSocket not connected. Cannot send. ReadyState:', ws.current?.readyState);
        }
    }, []); // Depends only on ws ref state (implicitly)

    // Effect to connect on mount and disconnect on unmount
    useEffect(() => {
        connect(); // Connect when hook is first used
        // Cleanup function to disconnect when component unmounts
        return () => {
            disconnect();
        };
    }, [connect, disconnect]); // Re-run if connect/disconnect functions change (they won't here)

    return { isConnected, lastMessage, sendMessage, connect, disconnect };
}
