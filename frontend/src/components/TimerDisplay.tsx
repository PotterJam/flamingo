import { useState, useEffect } from 'react';

function TimerDisplay({ endTime }: { endTime: number }) {
    const [remainingSeconds, setRemainingSeconds] = useState(0);

    useEffect(() => {
        let intervalId: number | null = null;

        function updateRemaining() {
            if (typeof endTime !== 'number' || endTime <= 0) {
                setRemainingSeconds(0);
                if (intervalId) clearInterval(intervalId);
                intervalId = null;
                return;
            }
            const now = Date.now();
            const remaining = Math.max(0, Math.round((endTime - now) / 1000));
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

        if (typeof endTime === 'number' && endTime > Date.now()) {
            updateRemaining();
            intervalId = setInterval(updateRemaining, 1000);
        } else {
            setRemainingSeconds(0);
        }

        return () => {
            if (intervalId) {
                clearInterval(intervalId);
            }
        };
    }, [endTime]);

    return (
        <div className="text-lg font-mono font-semibold text-gray-700" title="Time Remaining">
            <span role="img" aria-label="Timer" className="mr-1">⏱️</span>
            {remainingSeconds}s
        </div>
    );
}

export default TimerDisplay;
