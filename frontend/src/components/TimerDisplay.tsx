import { createSignal, createEffect, onCleanup } from 'solid-js';

function TimerDisplay(props: { endTime: number }) {
    const [remainingSeconds, setRemainingSeconds] = createSignal(0);

    createEffect(() => {
        let intervalId: NodeJS.Timeout | null = null;

        function updateRemaining() {
            if (typeof props.endTime !== 'number' || props.endTime <= 0) {
                setRemainingSeconds(0);
                if (intervalId) clearInterval(intervalId);
                intervalId = null;
                return;
            }
            const now = Date.now();
            const remaining = Math.max(
                0,
                Math.round((props.endTime - now) / 1000)
            );
            setRemainingSeconds(remaining);

            if (remaining === 0 && intervalId) {
                clearInterval(intervalId);
                intervalId = null;
            }
        }

        if (intervalId) {
            clearInterval(intervalId);
            intervalId = null;
        }

        if (typeof props.endTime === 'number' && props.endTime > Date.now()) {
            updateRemaining();
            intervalId = setInterval(updateRemaining, 1000);
        } else {
            setRemainingSeconds(0);
        }

        onCleanup(() => {
            if (intervalId) {
                clearInterval(intervalId);
            }
        });
    });

    return (
        <div
            class="font-mono text-lg font-semibold text-gray-700"
            title="Time Remaining"
        >
            <span role="img" aria-label="Timer" class="mr-1">
                ⏱️
            </span>
            {remainingSeconds()}s
        </div>
    );
}

export default TimerDisplay;
