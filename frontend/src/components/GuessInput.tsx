import { createSignal } from 'solid-js';

function GuessInput() {
    const [guess, setGuess] = createSignal('');

    return (
        <div class="flex gap-2">
            <input
                type="text"
                value={guess()}
                onInput={(e) => setGuess(e.target.value)}
                placeholder="Enter your guess..."
                class="flex-1 rounded border border-gray-300 p-2"
            />
            <button 
                type="submit"
                class="rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
            >
                Guess
            </button>
        </div>
    );
}

export default GuessInput;
