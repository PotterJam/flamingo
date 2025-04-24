import { useState } from 'react';

function GuessInput({ onGuess }: { onGuess: (guess: string) => void }) {
    const [currentGuess, setCurrentGuess] = useState('');

    const handleSubmit = (e: any) => {
        e.preventDefault();
        const guessToSend = currentGuess.trim();
        if (guessToSend) {
            onGuess(guessToSend);
            setCurrentGuess('');
        }
    };

    return (
        <form onSubmit={handleSubmit} className="flex gap-2">
            <input
                type="text"
                value={currentGuess}
                onChange={(e) => setCurrentGuess(e.target.value)}
                placeholder="Enter your guess"
                maxLength={50}
                className="flex-grow rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Enter your guess"
            />
            <button
                type="submit"
                className="rounded bg-blue-500 px-4 py-2 font-medium text-black transition duration-150 ease-in-out hover:bg-blue-600 focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!currentGuess.trim()}
            >
                Guess
            </button>
        </form>
    );
}

export default GuessInput;
