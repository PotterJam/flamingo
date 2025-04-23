import { writable } from 'svelte/store';

// Store for WebSocket connection status and messages
export const ws = writable(null); // Holds the WebSocket instance
export const wsConnected = writable(false);
export const lastMessage = writable(null); // Store the last received message

let socket = null;
// Ensure this URL points to your Go backend WebSocket endpoint
const wsUrl = 'ws://localhost:8080/ws';

/**
 * Establishes or re-establishes the WebSocket connection.
 */
export function connectWebSocket() {
    // Avoid creating multiple connections
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
        console.log('WebSocket already open or connecting.');
        return;
    }

    console.log('Attempting to connect WebSocket to:', wsUrl);
    socket = new WebSocket(wsUrl);
    ws.set(socket); // Store the instance in the writable store

    // WebSocket Event Listeners
    socket.onopen = () => {
        console.log('WebSocket connection established.');
        wsConnected.set(true); // Update connection status store
    };

    socket.onmessage = (event) => {
        try {
            const message = JSON.parse(event.data);
            console.log('Message received:', message);
            lastMessage.set(message); // Update last message store
        } catch (error) {
            console.error('Error parsing WebSocket message:', error, event.data);
        }
    };

    socket.onerror = (error) => {
        console.error('WebSocket error:', error);
        wsConnected.set(false); // Update connection status
        ws.set(null); // Clear the socket instance
        // Optional: Implement automatic reconnection logic here (e.g., using setTimeout with backoff)
    };

    socket.onclose = (event) => {
        console.log('WebSocket connection closed:', event.code, event.reason);
        wsConnected.set(false); // Update connection status
        ws.set(null); // Clear the socket instance
        // Optional: Notify user or attempt reconnection
    };
}

/**
 * Sends a message through the WebSocket connection.
 * @param {string} type - The message type identifier.
 * @param {object} payload - The data payload for the message.
 */
export function sendMessage(type, payload) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        const message = JSON.stringify({ type, payload });
        console.log('Sending message:', message);
        socket.send(message);
    } else {
        console.error('WebSocket is not connected. Cannot send message.');
        // Optional: Queue message or notify user
    }
}

// Note: Closing the WebSocket on component unmount is typically handled
// globally or when the entire application closes, not usually within this module itself.
// If needed, you could export a disconnect function:
// export function disconnectWebSocket() {
//   if (socket) {
//     socket.close();
//   }
// }