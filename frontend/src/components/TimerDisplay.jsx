import React, { useState, useEffect } from 'react';

function TimerDisplay({ endTime }) {
	const [remainingSeconds, setRemainingSeconds] = useState(0);

	useEffect(() => {
		let intervalId = null;

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

		// Clear previous interval if endTime changes
		if (intervalId) {
			clearInterval(intervalId);
			intervalId = null;
		}

		// Start new timer if valid endTime is provided and time remains
		if (typeof endTime === 'number' && endTime > Date.now()) {
			updateRemaining(); // Update immediately
			intervalId = setInterval(updateRemaining, 1000);
		} else {
			setRemainingSeconds(0); // Ensure display is 0 if time is already past or invalid
		}

		// Cleanup function for when component unmounts or endTime changes
		return () => {
			if (intervalId) {
				clearInterval(intervalId);
			}
		};
	}, [endTime]); // Re-run effect when endTime prop changes

	return (
		<div className="text-lg font-mono font-semibold text-gray-700" title="Time Remaining">
			<span role="img" aria-label="Timer" className="mr-1">⏱️</span>
			{remainingSeconds}s
		</div>
	);
}

export default TimerDisplay;