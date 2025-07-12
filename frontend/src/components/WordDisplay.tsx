import { Show } from 'solid-js';

interface WordDisplayProps {
    word?: string;
    wordOutline?: string[];
}

function WordDisplay(props: WordDisplayProps) {
    const word = () => props.word || '';
    const wordOutline = () => props.wordOutline || [];
    const wordDisplay = () =>
        word() ||
        wordOutline()
            .map((char) => char || '_')
            .join('');

    if (!word() && !wordOutline().length) {
        return null;
    }

    return (
        <div class="font-retro flex flex-1 flex-row justify-center gap-12 text-5xl text-amber-400">
            <p class="translate-y-0.75">{wordDisplay()}</p>
            <Show when={!word()}>
                <p class="translate-y-0.75">({wordOutline().length})</p>
            </Show>
        </div>
    );
}

export default WordDisplay;
