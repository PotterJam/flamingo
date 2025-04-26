import { useState } from 'react';
import { PrimaryButton } from './buttons/PrimaryButton';

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
                className="flex-1 rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Enter your guess"
            />
            <PrimaryButton
                type="submit"
                disabled={!currentGuess.trim()}
                className="flex-0"
            >
                Guess
            </PrimaryButton>
        </form>
    );
}

export default GuessInput;
