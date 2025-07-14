import { For } from 'solid-js';
import { PrimaryButton } from './buttons/PrimaryButton';

interface WordChoiceModalProps {
    wordChoices: string[];
    turnEndTime: number;
    chooseWord: (word: string) => void;
}

export const WordChoiceModal = (props: WordChoiceModalProps) => {
    return (
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm">
            <div class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl transition-all duration-300 ease-in-out">
                <div class="mb-4 flex items-center justify-between">
                    <h2 class="text-xl font-semibold text-gray-800">
                        Choose a Word
                    </h2>
                </div>
                <p class="mb-6 text-sm text-gray-600">
                    Select one of the words below to draw. Hurry!
                </p>
                <div class="flex flex-col items-center justify-center gap-4 sm:flex-row">
                    <For each={props.wordChoices}>
                        {(word) => (
                            <PrimaryButton
                                onClick={() => props.chooseWord(word)}
                                class="w-full sm:w-auto"
                            >
                                {word}
                            </PrimaryButton>
                        )}
                    </For>
                </div>
            </div>
        </div>
    );
};
