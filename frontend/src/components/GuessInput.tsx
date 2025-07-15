import { createSignal, Component } from 'solid-js';
import { autofocus } from '@solid-primitives/autofocus';
import { TextField, TextFieldInput, TextFieldLabel } from './ui/text-field';
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
        <form onSubmit={handleSubmit} class="p-2">
            <TextField
                value={currentGuess()}
                onChange={(e) => setCurrentGuess(e)}
                onSubmit={handleSubmit}
                class="flex flex-col gap-2"
            >
                <TextFieldLabel>
                    <div class="flex w-full flex-row justify-between px-1">
                        <p>Guess</p>
                        <p>{currentGuess().length}</p>
                    </div>
                </TextFieldLabel>
                <TextFieldInput
                    type="text"
                    maxlength={12}
                    use:autofocus
                    autofocus
                />
            </TextField>
        </form>
    );
};

export default GuessInput;
