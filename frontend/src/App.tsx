import { useState, useEffect, useMemo, useCallback } from 'react';
import { useWebSocket, Player, ErrorPayload, TurnEndPayload } from './hooks/useWebSocket';

import NameInput from './components/NameInput';
import PlayerList from './components/PlayerList';
import ChatBox from './components/ChatBox';
import Whiteboard from './components/Whiteboard';
import WordDisplay from './components/WordDisplay';
import TimerDisplay from './components/TimerDisplay';
import GuessInput from './components/GuessInput';
import StatusMessage from './components/StatusMessage';
import { create } from 'zustand/react';
import { Scaffolding } from './components/Scaffolding';

export interface ChatMessage {
    senderName: string;
    message: string;
    isSystem: boolean;
}

const CANVAS_WIDTH = 800;
const CANVAS_HEIGHT = 600;
const MIN_PLAYERS = 2;

type CurrentAppState = 'active'
    | 'waiting'
    | 'connecting'
    | 'joining'
    | 'enterName';

interface AppState {
    appState: CurrentAppState;
    setState: (newState: CurrentAppState) => void;
}

export const useAppStore = create<AppState>((set) => ({
    appState: 'connecting',
    setState: (newState) => set((_) => ({ appState: newState })),
}));

function App() {
    const { isConnected, lastMessage, sendMessage, connect } = useWebSocket();

    const appState = useAppStore((state) => state.appState);
    const setAppState = useAppStore((state) => state.setState);

    const [localPlayerId, setLocalPlayerId] = useState<string | null>(null);
    const [_localPlayerName, setLocalPlayerName] = useState<string | null>('');
    const [players, setPlayers] = useState<Player[]>([]);
    const [hostId, setHostId] = useState<string | null>(null);
    const [currentDrawerId, setCurrentDrawerId] = useState<string | null>(null);
    const [secretWord, setSecretWord] = useState('');
    const [wordLength, setWordLength] = useState(0);
    const [statusText, setStatusText] = useState('Connecting to server...');
    const [whiteboardKey, setWhiteboardKey] = useState(Date.now());
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


    const addChatMessage = useCallback((msgPayload: ChatMessage) => {
        setChatMessages(prevMessages => {
            const newMessages = [...prevMessages, msgPayload];

            return newMessages.length > 100 ? newMessages.slice(-100) : newMessages;
        });
    }, []);

    const getWordBlanks = useCallback((length: number) => {
        if (length <= 0) return '';
        return Array(length).fill('_').join(' ');
    }, []);

    const updateStatusText = useCallback(() => {
        let newStatus = statusText;

        if (appState === 'waiting' || appState === 'joining') {
            const host = players.find(p => p.isHost);
            const hostName = host ? host.name : "Someone";
            if (players.length < MIN_PLAYERS) {
                newStatus = `Waiting for more players... (${players.length}/${MIN_PLAYERS})`;
            } else if (isLocalPlayerHost) {
                newStatus = `You are the host. Start the game when ready! (${players.length} players)`;
            } else {
                newStatus = `Waiting for ${hostName} (Host) to start the game... (${players.length} players)`;
            }
            if (appState === 'joining') newStatus = 'Joining game... Please wait.';
        } else if (appState === 'active') {
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

        setStatusText(newStatus);
    }, [players, appState, isLocalPlayerHost, currentDrawerId, isLocalPlayerDrawer, secretWord, localPlayerId, statusText]);


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

                setLocalPlayerId(null);
                setLocalPlayerName('');
                setPlayers([]);
                setHostId(null);
                setCurrentDrawerId(null);
                setSecretWord('');
                setWordLength(0);
                setChatMessages([]);
                setTurnEndTime(null);


            }
        }
    }, [isConnected, appState, connect]);


    useEffect(() => {
        if (lastMessage) {
            console.log("Processing message in useEffect:", lastMessage);
            const message = lastMessage;

            switch (message.type) {
                case 'gameInfo': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received gameInfo with null payload");
                        break;
                    }
                    setLocalPlayerId(payload.yourId || null);
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || null);
                    setCurrentDrawerId(payload.currentDrawerId || null);
                    setWordLength(payload.wordLength || 0);
                    setTurnEndTime(payload.turnEndTime || null);
                    setSecretWord('');

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
                    if (!payload) {
                        console.error("Received playerUpdate with null payload");
                        break;
                    }
                    setPlayers(payload.players || []);
                    setHostId(payload.hostId || hostId);

                    if (appState === 'active' && (payload.players?.length ?? 0) < MIN_PLAYERS) {
                        console.log("Player count dropped below minimum, returning to waiting state.");
                        setCurrentDrawerId(null);
                        setTurnEndTime(null);
                        setWordLength(0);
                        setSecretWord('');
                        setAppState('waiting');
                    }

                    break;
                }
                case 'turnStart': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received turnStart with null payload");
                        break;
                    }
                    setCurrentDrawerId(payload.currentDrawerId);
                    setWordLength(payload.wordLength);
                    setSecretWord(payload.word || '');
                    setPlayers(payload.players || players);
                    setHostId(payload.players?.find(p => p.isHost)?.id || hostId);
                    setTurnEndTime(payload.turnEndTime);
                    setAppState('active');
                    setWhiteboardKey(Date.now());
                    break;
                }
                case 'playerGuessedCorrectly': {
                    const payload = message.payload;
                    if (!payload) {
                        console.error("Received playerGuessedCorrectly with null payload");
                        break;
                    }
                    const { playerId } = payload;
                    setPlayers(prevPlayers =>
                        prevPlayers.map(p =>
                            p.id === playerId ? { ...p, hasGuessedCorrectly: true } : p
                        )
                    );
                    const guesser = players.find(p => p.id === playerId);
                    if (guesser) {
                        addChatMessage({
                            senderName: 'System',
                            message: `${guesser?.name ?? 'Unknown'} guessed the word!`,
                            isSystem: true
                        });
                    }
                    break;
                }
                case 'chat': {
                    const payload = message.payload as unknown as ChatMessage;
                    if (!payload) {
                        console.error("Received chat with null payload");
                        break;
                    }
                    addChatMessage(payload);
                    break;
                }
                case 'drawEvent': {
                    const payload = message.payload;
                    if (!payload) {
                        break;
                    }
                    break;
                }
                case 'turnEnd': {
                    const payload = message.payload as unknown as TurnEndPayload;
                    if (!payload) {
                        console.error("Received turnEnd with null payload");
                        break;
                    }
                    setTurnEndTime(null);
                    if (localPlayerId !== currentDrawerId) {
                        setWordLength(0);
                    }

                    setStatusText(`Word was: ${payload.correctWord}. Getting next turn ready...`);

                    setPlayers(prevPlayers => prevPlayers.map(p => ({ ...p, hasGuessedCorrectly: false })));
                    break;
                }
                case 'error': {
                    const payload = message.payload as unknown as ErrorPayload;
                    if (!payload) {
                        console.error("Received error with null payload");
                        break;
                    }
                    setStatusText(`Error: ${payload.message || 'Unknown error'}`);
                    addChatMessage({
                        senderName: 'System',
                        message: `Error: ${payload.message || 'Unknown error'}`,
                        isSystem: true
                    });
                    break;
                }
                default:
                    console.warn("Received unhandled message type:", message.type);
            }
        }
    }, [lastMessage, addChatMessage, localPlayerId, currentDrawerId, hostId, appState]);


    useEffect(() => {
        updateStatusText();
    }, [appState, players, currentDrawerId, hostId, isLocalPlayerHost, isLocalPlayerDrawer, secretWord, localPlayerId, updateStatusText]);



    const handleNameSet = useCallback((name: string) => {
        console.log("handleNameSet called with name:", name);
        if (name && isConnected) {
            setLocalPlayerName(name);
            sendMessage('setName', { name: name });
            setAppState('joining');
            setStatusText('Joining game... Please wait.');
            console.log("Sent setName, moved state to 'joining'.");
        } else {
            console.error("Cannot set name - invalid name or WebSocket disconnected.");
            setStatusText("Failed to set name. Please check connection and try again.");
        }
    }, [isConnected, sendMessage]);

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

    if (appState === 'enterName') {
        return (
            <Scaffolding>
                <NameInput onNameSet={handleNameSet} />
                <StatusMessage message={statusText} />
            </Scaffolding>
        );
    }

    if (!isConnected) {
        return (
            <Scaffolding>
                <div className="text-center mt-10">
                    <StatusMessage message={statusText} />
                </div>
            </Scaffolding>
        );
    }

    if (appState === 'joining' || !localPlayerId) {
        return (
            <Scaffolding>
                <div className="text-center mt-10">
                    <StatusMessage message={statusText} />
                    <p className="text-gray-500 animate-pulse mt-2">Waiting for server info...</p>
                </div>
            </Scaffolding>
        );
    }

    return (
        <Scaffolding>
            <div className="flex justify-center w-full flex-grow">
                <div className="flex flex-col lg:flex-row gap-4"
                    style={{ width: `${250 + CANVAS_WIDTH + 32}px` }}>
                    <aside
                        className="w-full lg:w-[250px] bg-white shadow-lg rounded-lg p-4 flex flex-col gap-4 order-2 lg:order-1 flex-shrink-0"
                        style={{ maxHeight: `${CANVAS_HEIGHT + 100}px` }}>
                        <h2 className="text-xl font-semibold border-b pb-2 flex-shrink-0">Players
                            ({players.length})</h2>
                        <div className="flex-shrink overflow-y-auto mb-4 min-h-0">
                            <PlayerList players={players} currentDrawerId={currentDrawerId}
                                hostId={hostId} />
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

                    <section
                        className="w-full lg:flex-1 bg-white shadow-lg rounded-lg p-6 flex flex-col order-1 lg:order-2">
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
                        <div
                            className="mb-4 border-2 border-black rounded overflow-hidden bg-white relative"
                            style={{
                                width: `${CANVAS_WIDTH}px`,
                                height: `${CANVAS_HEIGHT}px`
                            }}
                        >
                            <Whiteboard
                                key={whiteboardKey}
                                isDrawer={!!isLocalPlayerDrawer}
                                onDraw={handleDraw}
                                lastDrawEvent={lastMessage?.type === 'drawEvent' ? lastMessage.payload : null}
                                localPlayerIsDrawer={!!isLocalPlayerDrawer}
                                width={CANVAS_WIDTH}
                                height={CANVAS_HEIGHT}
                            />
                        </div>


                        <div className="mb-4 text-center flex-shrink-0">
                            <StatusMessage message={statusText} />
                        </div>

                        <div className="flex-shrink-0">
                            {canLocalPlayerGuess && (
                                <GuessInput onGuess={handleGuess} />
                            )}
                        </div>
                    </section>
                </div>
            </div >
        </Scaffolding >
    );
}

export default App;
