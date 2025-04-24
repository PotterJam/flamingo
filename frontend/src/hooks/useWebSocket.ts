import { useState, useEffect, useRef, useCallback } from 'react';
import { useAppStore } from '../App';
import { Player, SendMsg } from '../messages';

const WS_URL = 'ws://localhost:8080/ws';

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

export interface WebsocketMessage {
    type: string;
    payload: JankPayload;
}

export function useWebSocket() {
    const [isConnected, setIsConnected] = useState(false);
    const ws = useRef<WebSocket>(null); // Ref to hold the WebSocket instance

    const setLastMessage = useAppStore((s) => s.setLastMessage);

    const connect = useCallback(() => {
        if (
            ws.current &&
            (ws.current.readyState === WebSocket.OPEN ||
                ws.current.readyState === WebSocket.CONNECTING)
        ) {
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
                ws.current = null; // Clear the ref
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

    return { isConnected, sendMessage, connect, disconnect };
}
