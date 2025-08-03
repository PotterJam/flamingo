import { createSignal, For } from 'solid-js';
import { store } from '../../store';
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card';
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from '../ui/select';
import { Player } from '~/messages';
import {
    Slider,
    SliderFill,
    SliderLabel,
    SliderThumb,
    SliderTrack,
    SliderValueLabel,
} from '../ui/slider';
import { FiArrowLeft, FiArrowRight } from 'solid-icons/fi';

const getMedal = (index: number): string => {
    switch (index) {
        case 0:
            return '🥇';
        case 1:
            return '🥈';
        case 2:
            return '🥉';
        default:
            return '';
    }
};

export const GameEndScreen = () => {
    const [selectedPlayer, setSelectedPlayer] = createSignal<Player | null>(
        null
    );

    const finalPlayers = [...store.gameState.players].sort(
        (a, b) => b.score - a.score
    );

    return (
        <div class="flex h-full w-full items-center justify-center gap-10">
            <Card class="w-xs gap-2 bg-white">
                <CardHeader>
                    <CardTitle class="text-2xl">Scores</CardTitle>
                </CardHeader>
                <CardContent>
                    <ul>
                        <For each={finalPlayers}>
                            {(player, index) => (
                                <li class="flex items-center justify-between p-3 text-lg">
                                    <span class="flex items-center">
                                        <span class="mr-2 w-6 text-xl">
                                            {getMedal(index())}
                                        </span>
                                        <span class="font-medium text-gray-900">
                                            {player.name}
                                        </span>
                                    </span>
                                    <span class="font-semibold text-pink-500">
                                        {player.score}
                                    </span>
                                </li>
                            )}
                        </For>
                    </ul>
                </CardContent>
            </Card>
            <Card class="gap-6 bg-white">
                <CardHeader class="flex flex-row items-center gap-4">
                    <CardTitle class="text-xl">Drawings from</CardTitle>
                    <Select
                        value={selectedPlayer()}
                        onChange={setSelectedPlayer}
                        options={finalPlayers}
                        placeholder="Select a player..."
                        optionValue="id"
                        optionTextValue="name"
                        itemComponent={(props) => (
                            <SelectItem item={props.item}>
                                {props.item.rawValue.name}
                            </SelectItem>
                        )}
                    >
                        <SelectTrigger class="mt-1 w-64">
                            <SelectValue<Player>>
                                {(state) => state.selectedOption().name}
                            </SelectValue>
                        </SelectTrigger>
                        <SelectContent />
                    </Select>
                </CardHeader>
                <CardContent>
                    <div class="flex flex-row items-center">
                        <button>
                            <FiArrowLeft class="size-6"/>
                        </button>
                        <p class="w-full text-center text-2xl font-semibold">
                            Magnet
                        </p>
                        <button>
                            <FiArrowRight  class="size-6"/>
                        </button>
                    </div>
                    <div class="mt-2 h-[500px] w-[700px] border-2" />
                    <Slider
                        minValue={1}
                        maxValue={5}
                        defaultValue={[3]}
                        class="mt-6 space-y-3"
                    >
                        <SliderTrack>
                            <SliderFill />
                            <SliderThumb />
                        </SliderTrack>
                    </Slider>
                </CardContent>
            </Card>
        </div>
    );
};
