import { For } from 'solid-js';
import { actions, store } from '../../store';
import { MIN_PLAYERS } from '../../App';
import { Card } from '../ui/card';
import { Button } from '../ui/button';
import {
    Slider,
    SliderFill,
    SliderLabel,
    SliderThumb,
    SliderTrack,
    SliderValueLabel,
} from '../ui/slider';
import { Label } from '../ui/label';

export const LobbyScreen = () => {
    const isHost = () =>
        store.gameState.localPlayerId === store.gameState.hostId;
    const canHostStartGame = () =>
        isHost() && store.gameState.players.length >= MIN_PLAYERS;

    const copyRoomName = () => {
        navigator.clipboard.writeText(store.roomId || '');
    };

    const handleStartGame = () => {
        if (canHostStartGame()) {
            store.sendMessage({
                type: 'startGame',
                payload: { roundCount: store.roundCount },
            });
        } else {
            console.warn('Start game attempted but conditions not met.');
        }
    };

    return (
        <div class="flex h-full w-full flex-grow items-center justify-center">
            <Card class="flex h-3/5 w-full max-w-2xl flex-row gap-0 bg-white p-0">
                <div class="flex flex-1 flex-col gap-4 border-r-2 border-blue-950 p-4">
                    <h2 class="text-xl font-bold">Players</h2>
                    <div class="overflowy-auto h-full">
                        <ul class="space-y-2">
                            <For each={store.gameState.players}>
                                {(player) => {
                                    return <li>{player.name}</li>;
                                }}
                            </For>
                        </ul>
                    </div>
                </div>
                <div class="flex h-full w-full flex-3 flex-col gap-4 p-4">
                    <Slider
                        minValue={1}
                        maxValue={5}
                        defaultValue={[3]}
                        value={[store.roundCount]}
                        onChange={(x) => actions.setRoundCount(x[0])}
                        class="space-y-3"
                    >
                        <div class="flex w-full justify-between">
                            <SliderLabel>Rounds</SliderLabel>
                            <SliderValueLabel />
                        </div>
                        <SliderTrack>
                            <SliderFill />
                            <SliderThumb />
                        </SliderTrack>
                    </Slider>

                    <div class="mt-auto flex w-full flex-col gap-4">
                        <div>
                            <Label>Room name</Label>
                            <div class="flex flex-row items-center justify-between">
                                <p class="text-l font-bold">{store.roomId}</p>
                                <Button
                                    variant="outline-no-shadow"
                                    onClick={copyRoomName}
                                >
                                    Copy
                                </Button>
                            </div>
                        </div>
                        <Button
                            variant="default"
                            onClick={handleStartGame}
                            disabled={!canHostStartGame()}
                        >
                            Start Game
                        </Button>
                    </div>
                </div>
            </Card>
        </div>
    );
};
