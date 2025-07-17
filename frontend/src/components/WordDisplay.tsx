import { store } from '../store';

function WordDisplay() {
    const word = () => store.gameState.word;
    const wordOutline = () => store.gameState.wordOutline ?? [];

    const wordDisplay = () =>
        word() ||
        wordOutline()
            .map((char) => (char ? char.toUpperCase() : '_'))
            .join('');

    if (!word() && !wordOutline().length) {
        return null;
    }

    return (
        <p class="flex flex-1 flex-row justify-center text-3xl font-black tracking-widest text-white">
            {word() ? word()?.toUpperCase() : wordDisplay()}
        </p>
    );
}

export default WordDisplay;
