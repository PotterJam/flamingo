import { For, Show } from 'solid-js';
import { actions, store } from '../../store';
import { OutlineButton } from '../buttons/OutlineButton';
import { PrimaryButton } from '../buttons/PrimaryButton';
import { CANVAS_HEIGHT } from '../Game';
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
                <div class="flex flex-1 flex-col gap-4 border-r-2 border-black p-4">
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
                    <div class="flex flex-row items-center justify-between">
                        <p class="text-l font-bold text-blue-400">
                            {store.roomId}
                        </p>
                        <OutlineButton class="w-20" onClick={copyRoomName}>
                            Copy
                        </OutlineButton>
                    </div>

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

                    <Button
                        variant="default"
                        class="mt-auto"
                        onClick={handleStartGame}
                        disabled={!canHostStartGame()}
                    >
                        Start Game
                    </Button>
                </div>
            </Card>
        </div>
    );
};
