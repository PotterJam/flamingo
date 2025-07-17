import { For } from 'solid-js';
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from './ui/card';
import { Button } from './ui/button';

interface WordChoiceModalProps {
    wordChoices: string[];
    turnEndTime: number;
    chooseWord: (word: string) => void;
}

export const WordChoiceModal = (props: WordChoiceModalProps) => {
    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-pink-950/30 backdrop-blur-sm">
            <Card class="bg-white">
                <CardHeader>
                    <CardTitle>Choose a word</CardTitle>
                    <CardDescription>
                        Select a word from below to draw
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <div class="flex flex-col items-center justify-center gap-4 sm:flex-row">
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
