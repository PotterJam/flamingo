import { Component } from 'solid-js';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../Game';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import Whiteboard from '../Whiteboard';
import GuessInput from '../GuessInput';
import { store } from '../../store';
import { GameHeader } from '../GameHeader';
import { Card, CardContent } from '../ui/card';
import { Separator } from '../ui/separator';

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
        <div class="flex h-[675px] w-full max-w-[1200px] justify-center gap-4">
            <Card class="w-full flex-1 bg-white p-0">
                <CardContent class="flex h-full w-full flex-col p-0">
                    <h2 class="p-2 text-lg font-bold">Players</h2>
                    <div class="min-h-0 flex-grow overflow-y-auto">
                        <PlayerList />
                    </div>
                </CardContent>
            </Card>

            <div class="flex w-[700px] flex-0 flex-col gap-2">
                <Card class="mb-4 flex items-center justify-between gap-4 bg-pink-400 p-2">
                    <CardContent class="w-full">
                        <GameHeader />
                    </CardContent>
                </Card>
                <Card class="bg-white p-0">
                    <CardContent class="p-0">
                        <div class="relative overflow-hidden bg-white">
                            <Whiteboard
                                width={CANVAS_WIDTH}
                                height={CANVAS_HEIGHT}
                            />
                        </div>
                    </CardContent>
                </Card>
            </div>

            <Card class="w-full flex-1 bg-white p-0">
                <CardContent class="flex h-full w-full flex-col p-0">
                    <div class="flex h-full w-full flex-1 flex-col">
                        <ChatBox />
                        <Separator />
                        <GuessInput onGuess={handleGuess} />
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};
