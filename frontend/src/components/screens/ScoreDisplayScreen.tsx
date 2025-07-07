import { For, Show } from 'solid-js';
import { store } from '../../store';

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
        <Show when={store.gameState.scoreDisplay}>
            <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm">
                <div class="w-full max-w-md rounded-lg bg-white p-8 text-center shadow-xl">
                    <h1 class="mb-4 text-3xl font-bold text-gray-800">
                        Round Complete!
                    </h1>
                    <p class="mb-6 text-lg text-gray-600">
                        The word was:{' '}
                        <span class="font-bold text-blue-600">
                            {store.gameState.scoreDisplay!.correctWord}
                        </span>
                    </p>
                    <h2 class="mb-4 text-xl font-semibold text-gray-700">
                        Points Earned This Round:
                    </h2>
                    <ul class="space-y-2">
                        <For each={store.gameState.scoreDisplay!.scoreGains}>
                            {(scoreGain, index) => (
                                <li class="flex items-center justify-between rounded-md bg-gray-50 p-3 shadow-sm">
                                    <span class="flex items-center">
                                        <span class="mr-3 w-8 text-lg font-bold">
                                            {getPositionIcon(index())}
                                        </span>
                                        <span class="font-medium text-gray-900">
                                            {scoreGain.playerName}
                                        </span>
                                    </span>
                                    <span
                                        class={`text-lg font-bold ${getScoreChangeColor(scoreGain.scoreGain)}`}
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
                </div>
            </div>
        </Show>
    );
};

