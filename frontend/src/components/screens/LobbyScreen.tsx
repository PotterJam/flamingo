import { For, Show, createSignal } from 'solid-js';
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
import {
    NumberField,
    NumberFieldDecrementTrigger,
    NumberFieldErrorMessage,
    NumberFieldGroup,
    NumberFieldIncrementTrigger,
    NumberFieldInput,
    NumberFieldLabel,
} from '../ui/number-field';
import { FaSolidMinus, FaSolidPlus } from 'solid-icons/fa';

export const LobbyScreen = () => {
    const [nameCopied, setNameCopied] = createSignal(false);
    const [linkCopied, setLinkCopied] = createSignal(false);
    const [roundLength, setRoundLength] = createSignal('45');

    const isHost = () =>
        store.gameState.localPlayerId === store.gameState.hostId;
    const canHostStartGame = () =>
        isHost() && store.gameState.players.length >= MIN_PLAYERS;

    const copyRoomName = () => {
        navigator.clipboard.writeText(store.roomId || '');
        setNameCopied(true);
        setTimeout(() => setNameCopied(false), 2000);
    };

    const copyRoomLink = () => {
        const roomLink = `${window.location.origin}/join/${store.roomId}`;
        navigator.clipboard.writeText(roomLink);
        setLinkCopied(true);
        setTimeout(() => setLinkCopied(false), 2000);
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
                <Show
                    when={isHost()}
                    fallback={
                        <div class="my-auto flex-3 text-center align-middle">
                            The host is configuring the game
                        </div>
                    }
                >
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
                        <NumberField
                            validationState={
                                store.roundLength < 30 ? 'invalid' : 'valid'
                            }
                            value={roundLength()}
                            onChange={(x) => {
                                setRoundLength(x);
                                if (x && !!parseInt(x)) {
                                    actions.setRoundLength(parseInt(x));
                                }
                            }}
                            class="w-full"
                        >
                            <NumberFieldLabel>Round length(s)</NumberFieldLabel>
                            <NumberFieldGroup class="w-48 my-1">
                                <NumberFieldInput />
                                <NumberFieldIncrementTrigger>
                                    <FaSolidPlus class="size-3" />
                                </NumberFieldIncrementTrigger>
                                <NumberFieldDecrementTrigger>
                                    <FaSolidMinus class="size-3" />
                                </NumberFieldDecrementTrigger>
                            </NumberFieldGroup>
                            <NumberFieldErrorMessage class="w-full">
                                Round length must be greater than 30 seconds
                            </NumberFieldErrorMessage>
                        </NumberField>

                        <div class="mt-auto flex w-full flex-col gap-4">
                            <div>
                                <Label>Room name</Label>
                                <div class="flex flex-row items-center justify-between">
                                    <p class="text-l font-bold">
                                        {store.roomId}
                                    </p>
                                    <div>
                                        <Button
                                            variant="ghost"
                                            onClick={copyRoomName}
                                            class="w-24"
                                        >
                                            {nameCopied()
                                                ? 'Copied!'
                                                : 'Copy name'}
                                        </Button>
                                        <Button
                                            variant="outline-no-shadow"
                                            onClick={copyRoomLink}
                                            class="w-24"
                                        >
                                            {linkCopied()
                                                ? 'Copied!'
                                                : 'Copy link'}
                                        </Button>
                                    </div>
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
                </Show>
            </Card>
        </div>
    );
};
