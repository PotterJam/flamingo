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

    return (
        <div class="font-retro flex-1 translate-y-0.75 text-5xl text-amber-400">
            <p>{wordDisplay()}</p>
        </div>
    );
}

export default WordDisplay;
