import { createSignal, Component } from 'solid-js';
import { autofocus } from '@solid-primitives/autofocus';
autofocus;

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
        <form onSubmit={handleSubmit}>
            <div class="relative">
                <input
                    type="text"
                    value={currentGuess()}
                    onInput={(e) =>
                        setCurrentGuess((e.target as HTMLInputElement).value)
                    }
                    placeholder=""
                    maxLength={50}
                    class="w-full rounded border border-gray-300 px-2 py-2 pr-8 text-sm transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                    aria-label="Type message or guess"
                    use:autofocus
                    autofocus
                />
                {currentGuess().length > 0 && (
                    <div class="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 text-xs text-gray-500">
                        {currentGuess().length}
                    </div>
                )}
            </div>
        </form>
    );
};

export default GuessInput;
