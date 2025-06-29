import { createSignal, Component } from 'solid-js';
import { PrimaryButton } from './buttons/PrimaryButton';

interface GuessInputProps {
    onGuess: (guess: string) => void;
}

const GuessInput: Component<GuessInputProps> = ({ onGuess }) => {
    const [currentGuess, setCurrentGuess] = createSignal('');

    const handleSubmit = (e: Event) => {
        e.preventDefault();
        const guessToSend = currentGuess().trim();
        if (guessToSend) {
            onGuess(guessToSend);
            setCurrentGuess('');
        }
    };

    return (
        <form onSubmit={handleSubmit} class="flex gap-1">
            <input
                type="text"
                value={currentGuess()}
                onInput={(e) => setCurrentGuess((e.target as HTMLInputElement).value)}
                placeholder="Type message or guess..."
                maxLength={50}
                class="flex-1 min-w-0 rounded border border-gray-300 px-2 py-2 text-sm transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Type message or guess"
            />
            <PrimaryButton
                type="submit"
                disabled={!currentGuess().trim()}
                class="flex-shrink-0 px-2 py-2 text-xs w-12"
            >
                Send
            </PrimaryButton>
        </form>
    );
};

export default GuessInput;