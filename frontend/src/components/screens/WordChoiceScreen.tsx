import { Show } from 'solid-js';
import { GuessingScreen } from './GuessingScreen';
import { WordChoiceModal } from '../WordChoiceModal';
import { actions, store } from '../../store';

export const WordChoiceScreen = () => {
    const isLocalPlayerDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;
    const showWordChoiceModal = () =>
        isLocalPlayerDrawer() &&
        store.gameState.wordChoices &&
        !store.gameState.word &&
        store.gameState.turnEndTime;

    const handleWordChosen = (chosenWord: string) => {
        actions.handleSelectRoundWord(chosenWord);
    };

    return (
        <>
            <GuessingScreen />
            <Show when={showWordChoiceModal()}>
                <WordChoiceModal
                    wordChoices={store.gameState.wordChoices!}
                    turnEndTime={store.gameState.turnEndTime!}
                    chooseWord={handleWordChosen}
                />
            </Show>
        </>
    );
};
