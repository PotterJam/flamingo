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
import { useTimer } from '../hooks/useTimer';

interface WordChoiceModalProps {
    wordChoices: string[];
    turnEndTime: number;
    chooseWord: (word: string) => void;
}

export const WordChoiceModal = (props: WordChoiceModalProps) => {
    const remainingSeconds = useTimer(() => store.gameState.turnEndTime);

    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-pink-950/30 backdrop-blur-sm">
            <Card class="min-w-xs bg-white">
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
                    <div class="flex flex-row items-center justify-evenly gap-4">
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
