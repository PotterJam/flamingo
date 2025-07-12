import { createSignal, createEffect, onCleanup } from 'solid-js';

function TimerDisplay(props: { endTime: number }) {
    const [remainingSeconds, setRemainingSeconds] = createSignal(0);

    createEffect(() => {
        const updateTimer = () => {
            const now = Date.now();
            const remaining = Math.max(
                0,
                Math.round((props.endTime - now) / 1000)
            );
            setRemainingSeconds(remaining);
        };

        updateTimer();
        const interval = setInterval(updateTimer, 1000);

        onCleanup(() => clearInterval(interval));
    });

    return (
        <div class="font-retro translate-y-0.75 text-2xl font-semibold text-amber-400">
            {remainingSeconds()}
        </div>
    );
}

export default TimerDisplay;
