import { useState } from 'react';

function GuessInput({ onGuess }: { onGuess: (guess: string) => void }) {
    const [currentGuess, setCurrentGuess] = useState('');

    const handleSubmit = (e: any) => {
        e.preventDefault();
        const guessToSend = currentGuess.trim();
        if (guessToSend) {
            onGuess(guessToSend);
            setCurrentGuess(''); // Clear input
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
                className="flex-grow p-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500 transition duration-150 ease-in-out"
                aria-label="Enter your guess"
            />
            <button
                type="submit"
                className="px-4 py-2 bg-blue-500 text-black font-medium rounded hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 transition duration-150 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={!currentGuess.trim()}
            >
                Guess
            </button>
        </form>
    );
}

export default GuessInput;
