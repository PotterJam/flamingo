import { For } from 'solid-js';
import { store } from '../../store';
import { GuessingScreen } from './GuessingScreen';
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '../ui/card';

const getPositionIcon = (index: number): string => {
    switch (index) {
        case 0:
            return '🥇';
        case 1:
            return '🥈';
        case 2:
            return '🥉';
        default:
            return `${index + 1}.`;
    }
};

const getScoreChangeColor = (scoreGain: number): string => {
    if (scoreGain > 0) return 'text-green-600';
    if (scoreGain === 0) return 'text-gray-500';
    return 'text-red-600';
};

const getScoreChangeText = (scoreGain: number): string => {
    if (scoreGain > 0) return `+${scoreGain}`;
    if (scoreGain === 0) return '0';
    return `${scoreGain}`;
};

export const ScoreDisplayScreen = () => {
    return (
        <>
            <GuessingScreen />
            <div class="fixed inset-0 z-50 flex items-center justify-center bg-pink-950/30 backdrop-blur-sm">
                <Card class="w-sm gap-4 bg-white">
                    <CardHeader>
                        <CardTitle class="text-2xl">Round over</CardTitle>
                        <CardDescription>
                            <p class="text-lg text-gray-600">
                                The word was{' '}
                                <span class="font-bold text-pink-500">
                                    {store.gameState.scoreDisplay!.correctWord}
                                </span>
                            </p>
                        </CardDescription>
                    </CardHeader>
                    <CardContent>
                        <ul>
                            <For
                                each={store.gameState.scoreDisplay!.scoreGains}
                            >
                                {(scoreGain, index) => (
                                    <li class="flex items-center justify-between px-3 py-2">
                                        <span class="flex items-center">
                                            <span class="mr-2 w-6 text-lg font-bold">
                                                {getPositionIcon(index())}
                                            </span>
                                            <span class="font-medium text-gray-900">
                                                {scoreGain.playerName}
                                            </span>
                                        </span>
                                        <span
                                            class={`font-semibold ${getScoreChangeColor(scoreGain.scoreGain)}`}
                                        >
                                            {getScoreChangeText(
                                                scoreGain.scoreGain
                                            )}{' '}
                                            pts
                                        </span>
                                    </li>
                                )}
                            </For>
                        </ul>
                    </CardContent>
                </Card>
            </div>
        </>
    );
};
