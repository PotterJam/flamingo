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
            <TextField class="flex flex-col gap-2">
                <TextFieldLabel>
                    <div class="flex w-full flex-row justify-between px-1">
                        <p>Guess</p>
                        <p>{currentGuess().length}</p>
                    </div>
                </TextFieldLabel>
                <input
                    type="text"
                    value={currentGuess()}
                    maxLength={15}
                    onInput={(e) => {
                        setCurrentGuess(e.currentTarget.value.trim());
                    }}
                    class="rounded-base ring-offset-background border-border bg-background placeholder:text-muted-foreground mt-1 flex h-10 w-full border-2 bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-blue-950 focus:ring-offset-2 focus:outline-none"
                    use:autofocus
                    autofocus
                />
            </TextField>
        </form>
    );
};

export default GuessInput;
