import { Show } from 'solid-js';
import { useAppStore } from '../../store';
import Whiteboard from '../Whiteboard';
import PlayerList from '../PlayerList';
import ChatBox from '../ChatBox';
import GuessInput from '../GuessInput';
import { CANVAS_WIDTH, CANVAS_HEIGHT } from '../Game';

export const GuessingScreen = () => {
    const store = useAppStore();

    return (
        <div class="flex h-screen w-full flex-col gap-4 p-4">
            <div class="flex flex-1 gap-4">
                <div class="flex flex-col">
                    <Whiteboard 
                        width={CANVAS_WIDTH}
                        height={CANVAS_HEIGHT}
                    />
                </div>
                <div class="flex w-80 flex-col gap-4">
                    <div class="flex-1 rounded-lg bg-white p-4 shadow-lg">
                        <h2 class="mb-2 text-lg font-semibold">Players</h2>
                        <PlayerList
                            players={store.gameState.players}
                            currentDrawerId={store.gameState.currentDrawerId}
                            hostId={store.gameState.hostId}
                        />
                    </div>
                    <div class="flex-1 rounded-lg bg-white p-4 shadow-lg">
                        <h2 class="mb-2 text-lg font-semibold">Chat</h2>
                        <ChatBox />
                        <div class="mt-2">
                            <GuessInput />
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};
