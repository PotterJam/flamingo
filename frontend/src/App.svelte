<script>
	import { onMount } from 'svelte';
	// Import stores and functions from the WebSocket module
	import { ws, wsConnected, lastMessage, connectWebSocket, sendMessage } from './lib/websocket.js';
	// Import child components
	import Whiteboard from './lib/Whiteboard.svelte';
	import WordDisplay from './lib/WordDisplay.svelte';
	import GuessInput from './lib/GuessInput.svelte';
	import StatusMessage from './lib/StatusMessage.svelte';

	// --- Component State ---
	let gameState = 'connecting'; // Overall game state: 'connecting', 'waiting', 'drawing', 'guessing', 'gameOver'
	let playerRole = null; // Player's role: null, 'drawer', 'guesser'
	let secretWord = ''; // The word to be drawn (for drawer)
	let wordLength = 0; // Length of the word (for guesser)
	let gameOverInfo = null; // Stores details when game ends: { correct: boolean, word: string }
	let statusText = 'Connecting to server...'; // User-facing status message
	let whiteboardKey = Date.now(); // Key to force re-rendering of the Whiteboard component

	// --- Component Reference ---
	let whiteboardComponent; // Reference to the Whiteboard child component instance (for calling methods)

	// --- Lifecycle ---
	onMount(() => {
		// Initiate WebSocket connection when the App component mounts
		connectWebSocket();
	});

	// --- Reactive Logic ---

	// React to changes in WebSocket connection status ($wsConnected store)
	$: if ($wsConnected) {
		// Actions when connection is established
		if (gameState === 'connecting') {
			// If we were in the initial connecting state, we now wait for the backend
			// to send us a 'waiting' or 'assignRole' message.
			// statusText = 'Connected! Waiting for server...'; // Optional intermediate state
		}
	} else {
		// Actions when connection is lost
		if (gameState !== 'connecting') { // Avoid resetting if already 'connecting'
			gameState = 'connecting'; // Reset game state
			statusText = 'Disconnected. Trying to reconnect...'; // Update status
			// Reset player-specific states
			playerRole = null;
			secretWord = '';
			wordLength = 0;
			gameOverInfo = null;
			// Optional: Implement automatic reconnection attempt trigger here
			// setTimeout(connectWebSocket, 5000); // Example: Try reconnecting after 5 seconds
		}
	}

	// React to new messages received via WebSocket ($lastMessage store)
	$: if ($lastMessage) {
		// Process the latest message
		handleMessage($lastMessage);
	}

	// --- Message Handling ---

	/**
	 * Processes incoming messages from the WebSocket server and updates component state.
	 * @param {object} message - The parsed message object { type: string, payload: object }.
	 */
	function handleMessage(message) {
		console.log("Handling message in App.svelte:", message); // For debugging
		switch (message.type) {
			case 'waiting':
				gameState = 'waiting';
				statusText = 'Waiting for another player...';
				playerRole = null; // Ensure no role is assigned
				gameOverInfo = null; // Clear previous game over info
				whiteboardKey = Date.now(); // Force whiteboard reset
				break;
			case 'assignRole':
				// Assign role based on payload
				playerRole = message.payload.role;
				if (playerRole === 'drawer') {
					secretWord = message.payload.word;
					wordLength = 0; // Clear guesser-specific state
					gameState = 'drawing';
					statusText = 'You are the Drawer! Draw the word.';
				} else if (playerRole === 'guesser') {
					secretWord = ''; // Clear drawer-specific state
					wordLength = message.payload.wordLength;
					gameState = 'guessing';
					statusText = 'You are the Guesser! Guess the drawing.';
				}
				gameOverInfo = null; // Clear previous game over info
				whiteboardKey = Date.now(); // Force whiteboard reset for the new game
				break;
			case 'drawEvent':
				// Forward drawing events to the Whiteboard component if the current player is the guesser
				if (gameState === 'guessing' && whiteboardComponent) {
					// Call the public method on the Whiteboard instance
					whiteboardComponent.handleDrawEvent(message.payload);
				}
				break;
			case 'guessResult':
				// Update status message for the guesser after an incorrect guess
				if (gameState === 'guessing') {
					statusText = `Guess '${message.payload.guess}': Incorrect. Keep trying!`;
					// Could add more sophisticated feedback (e.g., temporary highlight)
				}
				break;
			case 'gameOver':
				// Handle the end of the game
				gameState = 'gameOver';
				gameOverInfo = message.payload; // Store result { correct: bool, word: string }
				// Display appropriate game over message based on role and outcome
				if (playerRole === 'guesser' && message.payload.correct) {
					statusText = `Correct! The word was "${message.payload.word}". Game Over!`;
				} else if (playerRole === 'drawer' && message.payload.correct) {
					statusText = `The word "${message.payload.word}" was guessed! Game Over!`;
				} else {
					// Handle other game over scenarios (e.g., opponent disconnect handled by 'playerLeft')
					statusText = `Game Over! The word was "${message.payload.word}".`;
				}
				// Future enhancement: Add a "Play Again" button here, which could send a message to the backend.
				break;
			case 'playerLeft':
				// Handle opponent disconnection
				gameState = 'waiting'; // Return to waiting state
				statusText = 'Your opponent disconnected. Waiting for a new player...';
				// Reset player-specific states
				playerRole = null;
				secretWord = '';
				wordLength = 0;
				gameOverInfo = null;
				whiteboardKey = Date.now(); // Force whiteboard reset
				break;
			case 'error':
				// Display errors sent from the backend
				statusText = `Server Error: ${message.payload.message}`;
				// Consider resetting state based on error severity
				break;
			default:
				// Log unhandled message types for debugging
				console.warn("Received unhandled message type in App.svelte:", message.type);
		}
	}

	// --- Event Handlers from Child Components ---

	/**
	 * Handles the 'draw' event dispatched from the Whiteboard component.
	 * Sends the drawing data to the backend if the player is the drawer.
	 * @param {object} drawData - The drawing event details from Whiteboard.
	 */
	function handleDraw(drawData) {
		if (gameState === 'drawing') {
			sendMessage('drawEvent', drawData);
		}
	}

	/**
	 * Handles the 'guess' event dispatched from the GuessInput component.
	 * Sends the guess to the backend if the player is the guesser.
	 * @param {string} guess - The guess string from GuessInput.
	 */
	function handleGuess(guess) {
		if (gameState === 'guessing') {
			sendMessage('guess', { guess: guess });
		}
	}

	// --- Utility Functions ---

	/**
	 * Generates a string of underscores representing the word length for the guesser.
	 * @param {number} length - The length of the secret word.
	 * @returns {string} A string of underscores separated by spaces.
	 */
	function getWordBlanks(length) {
		if (length <= 0) return '';
		return Array(length).fill('_').join(' ');
	}

</script>

<main class="flex flex-col items-center justify-center min-h-screen bg-gray-100 p-4 font-sans">
	<h1 class="text-3xl font-bold mb-4 text-blue-600">Simple Scribblio</h1>

	{#if $wsConnected}
		<div class="w-full max-w-2xl bg-white shadow-lg rounded-lg p-6">
			<div class="mb-4 text-center">
				{#if playerRole === 'drawer'}
					<WordDisplay word={secretWord} />
				{:else if playerRole === 'guesser'}
					<WordDisplay blanks={getWordBlanks(wordLength)} length={wordLength}/>
				{:else}
					<div class="h-8"></div>
				{/if}
			</div>

			<div class="mb-4 border-2 border-black rounded overflow-hidden aspect-video bg-white">
				{#key whiteboardKey}
					<Whiteboard
						bind:this={whiteboardComponent} isDrawer={playerRole === 'drawer'} on:draw={event => handleDraw(event.detail)} />
				{/key}
			</div>

			<div class="mb-4 text-center">
				<StatusMessage message={statusText} /> </div>

			{#if playerRole === 'guesser' && gameState === 'guessing'}
				<GuessInput on:guess={event => handleGuess(event.detail)} /> {/if}

			{#if gameState === 'gameOver' && gameOverInfo}
				<div
					class="mt-4 p-4 rounded text-center"
					class:bg-green-100={gameOverInfo.correct} class:text-green-700={gameOverInfo.correct}
					class:bg-red-100={!gameOverInfo.correct} class:text-red-700={!gameOverInfo.correct}
				>
					<p class="font-semibold">Game Over!</p>
					<p>The word was: <span class="font-bold">{gameOverInfo.word}</span></p>
					</div>
			{/if}
		</div>
	{:else}
		<StatusMessage message={statusText} />
	{/if}
</main>

<style>
	/* Using Tailwind utility classes primarily, but global styles can go here */
	/* Example: */
	/* :global(body) { */
	/* font-family: 'Inter', sans-serif; */
	/* } */
</style>
