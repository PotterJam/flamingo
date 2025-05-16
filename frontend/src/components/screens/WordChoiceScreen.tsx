import { FC } from 'react';
import { useAppStore } from '../../store';
import { GuessingScreen } from './GuessingScreen';
import { WordChoiceModal } from '../WordChoiceModal';

export const WordChoiceScreen: FC = () => {
    const { currentDrawerId, localPlayerId, word, wordChoices, turnEndTime } =
        useAppStore((s) => s.gameState);
    const sendMessage = useAppStore((s) => s.sendMessage);

    const isLocalPlayerDrawer = localPlayerId === currentDrawerId;
    const showWordChoiceModal = isLocalPlayerDrawer && wordChoices && !word;

    const handleWordChosen = (chosenWord: string) => {
        sendMessage({
            type: 'selectRoundWord',
            payload: { word: chosenWord },
        });
    };

    return (
        <>
            <GuessingScreen />
            {showWordChoiceModal && wordChoices && turnEndTime && (
                <WordChoiceModal
                    wordChoices={wordChoices}
                    turnEndTime={turnEndTime}
                    chooseWord={handleWordChosen}
                />
            )}
        </>
    );
};
