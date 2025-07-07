import { Show } from 'solid-js';
import { GuessingScreen } from './GuessingScreen';
import { WordChoiceModal } from '../WordChoiceModal';
import { store } from '../../store';

export const WordChoiceScreen = () => {
    const isLocalPlayerDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;
    const showWordChoiceModal = () =>
        isLocalPlayerDrawer() &&
        store.gameState.wordChoices &&
        !store.gameState.word;

    const handleWordChosen = (chosenWord: string) => {
        store.sendMessage({
            type: 'selectRoundWord',
            payload: { word: chosenWord },
        });
    };

    return (
        <>
            <GuessingScreen />
            <Show
                when={
                    showWordChoiceModal() &&
                    store.gameState.wordChoices &&
                    store.gameState.turnEndTime
                }
            >
                <WordChoiceModal
                    wordChoices={store.gameState.wordChoices!}
                    turnEndTime={store.gameState.turnEndTime!}
                    chooseWord={handleWordChosen}
                />
            </Show>
        </>
    );
};
