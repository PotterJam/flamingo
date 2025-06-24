import { Show } from 'solid-js';

interface WordDisplayProps {
    word?: string;
    blanks?: string;
    length?: number;
}

function WordDisplay(props: WordDisplayProps) {
    const word = () => props.word || '';
    const blanks = () => props.blanks || '';
    const length = () => props.length || 0;

    return (
        <div class="flex min-h-[3rem] items-center justify-center rounded bg-gray-200 p-2 text-center text-2xl font-semibold tracking-widest select-none lg:text-3xl">
            <Show
                when={word()}
                fallback={
                    <Show
                        when={blanks()}
                        fallback={<span class="text-gray-400">&nbsp;</span>}
                    >
                        <span class="mr-2">{blanks()}</span>
                        <span class="text-sm text-gray-600">
                            ({length()} letters)
                        </span>
                    </Show>
                }
            >
                <span>{word()}</span>
            </Show>
        </div>
    );
}

export default WordDisplay;
