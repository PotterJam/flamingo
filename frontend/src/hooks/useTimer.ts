import { createSignal, createEffect, onCleanup, Accessor } from 'solid-js';

export function useTimer(endTime: Accessor<number | null>): Accessor<number> {
    const [remainingSeconds, setRemainingSeconds] = createSignal(0);

    createEffect(() => {
        const updateTimer = () => {
            const now = Date.now();
            const end = endTime();
            if (!end) {
                setRemainingSeconds(0);
                return;
            }
            const remaining = Math.max(0, Math.round((end - now) / 1000));
            setRemainingSeconds(remaining);
        };

        updateTimer();
        const interval = setInterval(updateTimer, 1000);

        onCleanup(() => clearInterval(interval));
    });

    return remainingSeconds;
}
