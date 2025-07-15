import { Component } from 'solid-js';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../Game';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import Whiteboard from '../Whiteboard';
import GuessInput from '../GuessInput';
import { store } from '../../store';
import { GameHeader } from '../GameHeader';
import { Card, CardContent } from '../ui/card';

export const GuessingScreen: Component = () => {
    const sendMessage = () => store.sendMessage;
    const players = () => store.gameState.players;
    const currentDrawerId = () => store.gameState.currentDrawerId;
    const localPlayerId = () => store.gameState.localPlayerId;

    const localPlayer = () => players().find((p) => p.id === localPlayerId());
    const isLocalPlayerDrawer = () => localPlayerId() === currentDrawerId();

    const handleGuess = (message: string) => {
        if (isLocalPlayerDrawer() || localPlayer()?.hasGuessedCorrectly) {
            sendMessage()({ type: 'chat', payload: { message: message } });
        } else {
            sendMessage()({ type: 'guess', payload: { guess: message } });
        }
    };

    return (
        <div class="mx-auto flex flex-grow justify-center gap-4">
            <Card class="w-full bg-white p-0">
                <CardContent class="flex h-full w-full flex-col p-0">
                    <div class="border-b-2 border-blue-950 p-2">
                        <h2 class="text-xl font-bold">Players</h2>
                        <div class="min-h-0 flex-grow overflow-y-auto">
                            <PlayerList />
                        </div>
                    </div>
                    <div class="h-full w-full flex flex-col flex-1">
                        <ChatBox />
                        <GuessInput onGuess={handleGuess} />
                    </div>
                </CardContent>
            </Card>

            {/* Game Area */}
            <section class="pixel-purple order-2 flex flex-col border-4 border-blue-300 border-t-blue-200 border-l-blue-200 p-6">
                <div class="mb-4 flex items-center justify-between gap-4">
                    <GameHeader />
                </div>
                <div class="relative overflow-hidden bg-white">
                    <Whiteboard width={CANVAS_WIDTH} height={CANVAS_HEIGHT} />
                </div>
            </section>
        </div>
    );
};
