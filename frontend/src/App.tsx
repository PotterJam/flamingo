import { useState, useEffect, useMemo, useCallback } from 'react';
import { useWebSocket, Player, ErrorPayload, TurnEndPayload } from './hooks/useWebSocket'; // Import the custom hook

// Import components
import NameInput from './components/NameInput';
import PlayerList from './components/PlayerList';
import ChatBox from './components/ChatBox';
import Whiteboard from './components/Whiteboard';
import WordDisplay from './components/WordDisplay';
import TimerDisplay from './components/TimerDisplay';
import GuessInput from './components/GuessInput';
import StatusMessage from './components/StatusMessage';

export interface ChatMessage {
    senderName: string;
    message: string;
    isSystem: boolean;
}

const MIN_PLAYERS = 2;

function App() {
    console.log("App component rendering...");

    const { isConnected, lastMessage, sendMessage, connect } = useWebSocket();

    const [appState, setAppState] = useState('connecting'); // 'connecting', 'enterName', 'joining', 'waiting', 'active'
    const [localPlayerId, setLocalPlayerId] = useState<string | null>(null);
    const [_localPlayerName, setLocalPlayerName] = useState<string | null>('');
    const [players, setPlayers] = useState<Player[]>([]); // {id, name, isHost, hasGuessedCorrectly}
    const [hostId, setHostId] = useState<string | null>(null);
    const [currentDrawerId, setCurrentDrawerId] = useState<string | null>(null);
    const [secretWord, setSecretWord] = useState('');
    const [wordLength, setWordLength] = useState(0);
    const [statusText, setStatusText] = useState('Connecting to server...');
    const [whiteboardKey, setWhiteboardKey] = useState(Date.now()); // For resetting whiteboard
    const [chatMessages, setChatMessages] = useState<ChatMessage[]>([]);
    const [turnEndTime, setTurnEndTime] = useState<number | null>(null);

    const isLocalPlayerHost = useMemo(() => localPlayerId && hostId && localPlayerId === hostId, [localPlayerId, hostId]);
    const isLocalPlayerDrawer = useMemo(() => localPlayerId && currentDrawerId && localPlayerId === currentDrawerId, [localPlayerId, currentDrawerId]);
    const canLocalPlayerGuess = useMemo(() => {
        if (appState !== 'active' || !localPlayerId || !currentDrawerId || localPlayerId === currentDrawerId || !Array.isArray(players)) {
            return false;
        }
        const localPlayer = players.find(p => p?.id === localPlayerId);
        return !localPlayer?.hasGuessedCorrectly;
    }, [appState, localPlayerId, currentDrawerId, players]);
    const canHostStartGame = useMemo(() => isLocalPlayerHost && appState === 'waiting' && players.length >= MIN_PLAYERS, [isLocalPlayerHost, appState, players]);

    // --- Utility Functions ---
    const addChatMessage = useCallback((msgPayload: ChatMessage) => {
        setChatMessages(prevMessages => {
            const newMessages = [...prevMessages, msgPayload];
            // Limit chat history
            return newMessages.length > 100 ? newMessages.slice(-100) : newMessages;
        });
    }, []); // No dependencies, safe to memoize

    const getWordBlanks = useCallback((length: number) => {
        if (length <= 0) return '';
        return Array(length).fill('_').join(' ');
    }, []); // No dependencies

    const updateStatusText = useCallback(() => {
        setAppState(currentAppState => { // Use functional update to get latest state
            let newStatus = statusText; // Start with current status

            if (currentAppState === 'waiting' || currentAppState === 'joining') {
                const host = players.find(p => p.isHost);
                const hostName = host ? host.name : "Someone";
                if (players.length < MIN_PLAYERS) {
                    newStatus = `Waiting for more players... (${players.length}/${MIN_PLAYERS})`;
                } else if (isLocalPlayerHost) {
                    newStatus = `You are the host. Start the game when ready! (${players.length} players)`;
                } else {
                    newStatus = `Waiting for ${hostName} (Host) to start the game... (${players.length} players)`;
                }
                if (currentAppState === 'joining') newStatus = 'Joining game... Please wait.';
            } else if (currentAppState === 'active') {
                const drawer = players.find(p => p.id === currentDrawerId);
                const drawerName = drawer ? drawer.name : 'Someone';
                if (isLocalPlayerDrawer) {
                    newStatus = `Your turn! Draw: ${secretWord}`;
                } else {
                    const localPlayer = players.find(p => p.id === localPlayerId);
                    if (localPlayer?.hasGuessedCorrectly) {
                        newStatus = `You guessed it! Waiting for others... (${drawerName} is drawing)`;
                    } else {
                        newStatus = `${drawerName} is drawing! Guess the word!`;
                    }
                }
            }
            // Only update if status actually changed
            if (newStatus !== statusText) {
                setStatusText(newStatus);
            }
            return currentAppState; // Return current state, no change here
        });
    }, [players, appState, isLocalPlayerHost, currentDrawerId, isLocalPlayerDrawer, secretWord, localPlayerId, statusText]); // Add dependencies

    // --- Effect for Connection Status ---
    useEffect(() => {
        if (isConnected) {
            if (appState === 'connecting') {
                console.log("WebSocket connected, moving to enterName state.");
                setAppState('enterName');
                setStatusText('Please enter your name.');
            }
        } else {
            if (appState !== 'connecting') {
                console.log("WebSocket disconnected.");
                setAppState('connecting');
                setStatusText('Disconnected. Trying to reconnect...');
                // Reset state
                setLocalPlayerId(null);
                setLocalPlayerName('');
                setPlayers([]);
                setHostId(null);
                setCurrentDrawerId(null);
                setSecretWord('');
                setWordLength(0);
                setChatMessages([]);
                setTurnEndTime(null);
                // Optional: Attempt reconnect
                // setTimeout(connect, 5000);
            }
        }
    }, [isConnected, appState, connect]); // Add connect dependency

    // --- Effect for Handling Messages ---
    useEffect(() => {
        if (lastMessage) {
            console.log("Processing message in useEffect:", lastMessage);
            const message = lastMessage; // Process the message

            switch (message.type) {
                case 'gameInfo': {
                    const payload = message.payload;
                    if (!payload) { console.error("Received gameInfo with null payload"); break; }
                    setLocalPlayerId(payload.yourId || null);
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || null);
                    setCurrentDrawerId(payload.currentDrawerId || null);
                    setWordLength(payload.wordLength || 0);
                    setTurnEndTime(payload.turnEndTime || null);
                    setSecretWord(''); // Word comes via turnStart

                    if (payload.isGameActive) {
                        setAppState('active');
                    } else {
                        setAppState('waiting');
                    }
                    console.log("Processed gameInfo. New State:", payload.isGameActive ? 'active' : 'waiting', "localId:", payload.yourId);
                    break;
                }
                case 'playerUpdate': {
                    const payload = message.payload;
                    if (!payload) { console.error("Received playerUpdate with null payload"); break; }
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || hostId); // Update host ID
                    // Check if game should end due to player count (backend also handles this)
                    setAppState(currentAppState => {
                        if (currentAppState === 'active' && (payload.players?.length ?? 0) < MIN_PLAYERS) {
                            console.log("Player count dropped below minimum, returning to waiting state.");
                            setCurrentDrawerId(null);
                            setTurnEndTime(null);
                            setWordLength(0);
                            setSecretWord('');
                            return 'waiting';
                        }
                        return currentAppState;
                    });
                    break;
                }
                case 'turnStart': {
                    const payload = message.payload;
                    if (!payload) { console.error("Received turnStart with null payload"); break; }
                    setCurrentDrawerId(payload.currentDrawerId);
                    setWordLength(payload.wordLength);
                    setSecretWord(payload.word || ''); // Will be empty if not drawer
                    setPlayers(payload.players || players); // Update player list (resets guess status)
                    setHostId(payload.players?.find(p => p.isHost)?.id || hostId); // Update host from list
                    setTurnEndTime(payload.turnEndTime);
                    setAppState('active');
                    setWhiteboardKey(Date.now()); // Reset whiteboard
                    break;
                }
                case 'playerGuessedCorrectly': {
                    const payload = message.payload;
                    if (!payload) { console.error("Received playerGuessedCorrectly with null payload"); break; }
                    const { playerId } = payload;
                    // setPlayers(prevPlayers =>
                    //     prevPlayers.map(p =>
                    //         p.id === playerId ? { ...p, hasGuessedCorrectly: true } : p
                    //     )
                    // );
                    const guesser = players.find(p => p.id === playerId); // Use current players state
                    // if (guesser) {
                        addChatMessage({ senderName: 'System', message: `${guesser?.name ?? 'Unknown'} guessed the word!`, isSystem: true });
                    //}
                    break;
                }
                case 'chat': {
                    const payload = message.payload as unknown as ChatMessage;
                    if (!payload) { console.error("Received chat with null payload"); break; }
                    addChatMessage(payload);
                    break;
                }
                case 'drawEvent': {
                    const payload = message.payload;
                    if (!payload) { break; }
                    // Need a way to pass this to Whiteboard without prop drilling excessively
                    // For now, maybe use a temporary state or event emitter?
                    // Or Whiteboard could consume lastMessage directly (less ideal)
                    // Let's skip direct handling here and assume Whiteboard handles it via props/context later
                    // console.log("Draw event received, needs handling in Whiteboard");
                    break;
                }
                case 'turnEnd': {
                    const payload = message.payload as unknown as TurnEndPayload;
                    if (!payload) { console.error("Received turnEnd with null payload"); break; }
                    setTurnEndTime(null);
                    if (localPlayerId !== currentDrawerId) { // Check if local player wasn't the drawer
                        setWordLength(0);
                    }
                    // Add system message revealing word (backend already does this via chat)
                    // addChatMessage({ senderName: 'System', message: `Word was: ${payload.correctWord}`, isSystem: true });
                    setStatusText(`Word was: ${payload.correctWord}. Getting next turn ready...`);
                    // Clear visual guess status
                    setPlayers(prevPlayers => prevPlayers.map(p => ({ ...p, hasGuessedCorrectly: false })));
                    break;
                }
                case 'error': {
                    const payload = message.payload as unknown as ErrorPayload;
                    if (!payload) { console.error("Received error with null payload"); break; }
                    setStatusText(`Error: ${payload.message || 'Unknown error'}`);
                    addChatMessage({ senderName: 'System', message: `Error: ${payload.message || 'Unknown error'}`, isSystem: true });
                    break;
                }
                default:
                    console.warn("Received unhandled message type:", message.type);
            }
        }
    }, [lastMessage, addChatMessage, players, localPlayerId, currentDrawerId, hostId]); // Add dependencies

    // --- Effect to update status text whenever relevant state changes ---
    useEffect(() => {
        updateStatusText();
    }, [appState, players, currentDrawerId, hostId, isLocalPlayerHost, isLocalPlayerDrawer, secretWord, localPlayerId, updateStatusText]); // Dependencies for status text


    // --- Event Handlers ---
    const handleNameSet = useCallback((name: string) => {
        console.log("handleNameSet called with name:", name);
        if (name && isConnected) {
            setLocalPlayerName(name); // Store locally
            sendMessage('setName', { name: name }); // Send to backend
            setAppState('joining'); // Move to intermediate state
            setStatusText('Joining game... Please wait.');
            console.log("Sent setName, moved state to 'joining'.");
        } else {
            console.error("Cannot set name - invalid name or WebSocket disconnected.");
            setStatusText("Failed to set name. Please check connection and try again.");
        }
    }, [isConnected, sendMessage]); // Dependencies

    const handleDraw = useCallback((drawData: any) => {
        if (isLocalPlayerDrawer && appState === 'active') {
            sendMessage('drawEvent', drawData);
        }
    }, [isLocalPlayerDrawer, appState, sendMessage]);

    const handleGuess = useCallback((guess: string) => {
        if (canLocalPlayerGuess) {
            sendMessage('guess', { guess: guess });
        }
    }, [canLocalPlayerGuess, sendMessage]);

    const handleStartGame = useCallback(() => {
        console.log("Start Game button clicked by host.");
        if (canHostStartGame) {
            sendMessage('startGame', null);
            setStatusText("Starting game...");
        } else {
            console.warn("Start game attempted but conditions not met.");
        }
    }, [canHostStartGame, sendMessage]);

    // --- Render Logic ---
    return (
        <main className="flex flex-col items-center justify-start min-h-screen bg-gray-100 p-4 font-sans">
            <h1 className="text-3xl font-bold mb-4 text-blue-600 flex-shrink-0">Scribblio Clone (React)</h1>

            {appState === 'enterName' ? (
                <>
                    <NameInput onNameSet={handleNameSet} />
                    <StatusMessage message={statusText} />
                </>
            ) : !isConnected && appState !== 'enterName' ? (
                <div className="text-center mt-10">
                    <StatusMessage message={statusText} />
                    {/* Optional: Add reconnect button */}
                    {/* <button onClick={connect} className="mt-4 ...">Reconnect</button> */}
                </div>
            ) : (
                <>
                    {appState === 'joining' || !localPlayerId ? (
                        <div className="text-center mt-10">
                            <StatusMessage message={statusText} />
                            <p className="text-gray-500 animate-pulse mt-2">Waiting for server info...</p>
                        </div>
                    ) : (
                        // Main Game Layout
                        <div className="flex flex-col lg:flex-row w-full max-w-6xl gap-4 flex-grow">
                            {/* Left Panel */}
                            <aside className="w-full lg:w-1/4 bg-white shadow-lg rounded-lg p-4 flex flex-col gap-4 order-2 lg:order-1 overflow-hidden max-h-[calc(100vh-8rem)]">
                                <h2 className="text-xl font-semibold border-b pb-2 flex-shrink-0">Players ({players.length})</h2>
                                <div className="flex-shrink overflow-y-auto mb-4 min-h-0">
                                    <PlayerList players={players} currentDrawerId={currentDrawerId} hostId={hostId} />
                                </div>

                                {canHostStartGame && (
                                    <button
                                        onClick={handleStartGame}
                                        className="px-4 py-2 bg-green-500 text-black font-semibold rounded hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-1 transition duration-150 ease-in-out flex-shrink-0"
                                    >
                                        Start Game ({players.length} players)
                                    </button>
                                )}

                                <h2 className={`text-xl font-semibold border-b pb-2 flex-shrink-0 ${!canHostStartGame ? 'mt-auto' : ''}`}>Chat</h2>
                                <div className="flex-grow overflow-y-hidden min-h-0">
                                    <ChatBox messages={chatMessages} />
                                </div>
                            </aside>

                            {/* Center Panel */}
                            <section className="w-full lg:w-3/4 bg-white shadow-lg rounded-lg p-6 flex flex-col order-1 lg:order-2">
                                {/* Top Bar */}
                                <div className="flex justify-between items-center mb-4 gap-4 flex-shrink-0">
                                    <div className="flex-1 text-center min-w-0">
                                        {(isLocalPlayerDrawer && appState === 'active') ? (
                                            <WordDisplay word={secretWord} />
                                        ) : (appState === 'active' && currentDrawerId) ? (
                                            <WordDisplay blanks={getWordBlanks(wordLength)} length={wordLength} />
                                        ) : (
                                            <div className="h-8 md:h-10"></div>
                                        )}
                                    </div>
                                    <div className="w-20 text-right flex-shrink-0">
                                        {(appState === 'active' && turnEndTime) && (
                                            <TimerDisplay endTime={turnEndTime} />
                                        )}
                                    </div>
                                </div>

                                <div className="mb-4 border-2 border-black rounded overflow-hidden bg-white flex-grow relative">
                                    <Whiteboard
                                        key={whiteboardKey} // Use key to force reset
                                        isDrawer={!!isLocalPlayerDrawer}
                                        onDraw={handleDraw}
                                        // Need to pass draw events received from WS to Whiteboard
                                        // This is tricky without context/emitter. For now, Whiteboard might need access to lastMessage.
                                        lastDrawEvent={lastMessage?.type === 'drawEvent' ? lastMessage.payload : null}
                                        localPlayerIsDrawer={!!isLocalPlayerDrawer} // Pass explicitly
                                    />
                                </div>

                                {/* Status */}
                                <div className="mb-4 text-center flex-shrink-0">
                                    <StatusMessage message={statusText} />
                                </div>

                                {/* Guess Input */}
                                <div className="flex-shrink-0">
                                    {canLocalPlayerGuess && (
                                        <GuessInput onGuess={handleGuess} />
                                    )}
                                </div>
                            </section>
                        </div>
                    )}
                </>
            )}
        </main>
    );
}

export default App;
