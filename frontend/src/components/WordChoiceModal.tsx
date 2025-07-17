import { For } from 'solid-js';
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from './ui/card';
import { Button } from './ui/button';
import { store } from '../store';
import { createEffect, createSignal, onCleanup } from 'solid-js';

interface WordChoiceModalProps {
    wordChoices: string[];
    turnEndTime: number;
    chooseWord: (word: string) => void;
}

export const WordChoiceModal = (props: WordChoiceModalProps) => {
    const turnEndTime = () => store.gameState.turnEndTime;
    const [remainingSeconds, setRemainingSeconds] = createSignal(0);

    createEffect(() => {
        const updateTimer = () => {
            const now = Date.now();
            const remaining = Math.max(
                0,
                Math.round((turnEndTime()! - now) / 1000)
            );
            setRemainingSeconds(remaining);
        };

        updateTimer();
        const interval = setInterval(updateTimer, 1000);

        onCleanup(() => clearInterval(interval));
    });

    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-pink-950/30 backdrop-blur-sm">
            <Card class="bg-white min-w-xs">
                <CardHeader>
                    <CardTitle>
                        <div class="flex w-full flex-row justify-between">
                            <span>Choose a word</span>
                            <span>{remainingSeconds()}s</span>
                        </div>
                    </CardTitle>
                    <CardDescription>
                        Select a word from below to draw
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <div class="flex items-center justify-evenly gap-4 flex-row">
                        <For each={props.wordChoices}>
                            {(word) => (
                                <Button
                                    variant="default"
                                    onClick={() => props.chooseWord(word)}
                                    class="w-full sm:w-auto"
                                >
                                    {word}
                                </Button>
                            )}
                        </For>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};
