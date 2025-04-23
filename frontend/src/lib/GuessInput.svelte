<script>
	import { createEventDispatcher } from 'svelte';

	// --- Event Dispatcher ---
	// Sends 'guess' event to App.svelte when guess is submitted.
	const dispatch = createEventDispatcher();

	// --- Local State ---
	let currentGuess = ''; // Bound to the input field value

	// --- Event Handler ---
	/**
	 * Handles the form submission, trims the guess, dispatches the event,
	 * and clears the input field.
	 */
	function submitGuess() {
		const guessToSend = currentGuess.trim(); // Trim whitespace
		if (guessToSend) { // Only dispatch if guess is not empty
			dispatch('guess', guessToSend); // Send the guess value to parent
			currentGuess = ''; // Reset the input field
		}
	}
</script>

<form on:submit|preventDefault={submitGuess} class="flex gap-2">
	<input
		type="text"
		bind:value={currentGuess}
		placeholder="Enter your guess"
		maxlength="50" class="flex-grow p-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500 transition duration-150 ease-in-out"
		aria-label="Enter your guess" />
	<button
		type="submit"
		class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 transition duration-150 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed"
		disabled={!currentGuess.trim()} >
		Guess
	</button>
</form>