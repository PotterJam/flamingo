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
        <form onSubmit={handleSubmit} class="flex gap-2">
            <input
                type="text"
                value={currentGuess()}
                onInput={(e) => setCurrentGuess((e.target as HTMLInputElement).value)}
                placeholder="Enter your guess"
                maxLength={50}
                class="flex-1 rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Enter your guess"
            />
            <PrimaryButton
                type="submit"
                disabled={!currentGuess().trim()}
                class="flex-0"
            >
                Guess
            </PrimaryButton>
        </form>
    );
};

export default GuessInput;