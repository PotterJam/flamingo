import { Show } from 'solid-js';
import { store } from '../store';

function WordDisplay() {
    const word = () => store.gameState.word;
    const wordOutline = () => store.gameState.wordOutline ?? [];
    const currentDrawerId = () => store.gameState.currentDrawerId;
    const localPlayerId = () => store.gameState.localPlayerId;

    const isLocalPlayerDrawer = () => localPlayerId() === currentDrawerId();

    const wordDisplay = () =>
        word() ||
        wordOutline()
            .map((char) => (char ? char.toUpperCase() : '_'))
            .join('');

    const letterCount = () => wordOutline().length;

    const showLetterCount = () =>
        !word() && !isLocalPlayerDrawer() && wordOutline().length > 0;

    if (!word() && !wordOutline().length) {
        return null;
    }

    return (
        <div class="flex flex-row items-center justify-center gap-4">
            <p class="text-3xl font-black tracking-widest text-white">
                {word() ? word()?.toUpperCase() : wordDisplay()}
            </p>
            <Show when={showLetterCount()}>
                <p class="text-md text-white">{letterCount()}</p>
            </Show>
        </div>
    );
}

export default WordDisplay;
