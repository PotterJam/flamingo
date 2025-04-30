// src/components/WordChoiceModal.tsx
import {FC} from 'react';
import {PrimaryButton} from './buttons/PrimaryButton';
import TimerDisplay from './TimerDisplay'; // Assuming TimerDisplay is in the same directory

interface WordChoiceModalProps {
    wordChoices: string[];
    turnEndTime: number;
    onWordChosen: (word: string) => void;
    isOpen: boolean;
}

export const WordChoiceModal: FC<WordChoiceModalProps> =
({
  wordChoices,
  turnEndTime,
  onWordChosen,
  isOpen,
}) => {
    if (!isOpen || !wordChoices || wordChoices.length === 0) {
        return null;
    }

    return (
        // Modal backdrop
        <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50 transition-opacity duration-300 ease-in-out">
            <div className="w-full max-w-md rounded-lg bg-white p-6 shadow-xl transition-all duration-300 ease-in-out">
                <div className="mb-4 flex items-center justify-between">
                    <h2 className="text-xl font-semibold text-gray-800">Choose a Word</h2>
                    <div className="w-20 text-right">
                        <TimerDisplay endTime={turnEndTime}/>
                    </div>
                </div>
                <p className="mb-6 text-sm text-gray-600">
                    Select one of the words below to draw. Hurry!
                </p>
                <div className="flex flex-col items-center justify-center gap-4 sm:flex-row">
                    {wordChoices.map((word) => (
                        <PrimaryButton
                            key={word}
                            onClick={() => onWordChosen(word)}
                            className="w-full sm:w-auto"
                        >
                            {word}
                        </PrimaryButton>
                    ))}
                </div>
            </div>
        </div>
    );
};