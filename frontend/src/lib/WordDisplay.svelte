<script>
	// --- Props ---
	// Passed down from App.svelte
	export let word = ''; // The actual secret word (if drawer)
	export let blanks = ''; // String of underscores (if guesser)
	export let length = 0; // Length of the word (if guesser)

</script>

<div class="text-2xl lg:text-3xl font-semibold tracking-widest text-center p-2 rounded bg-gray-200 min-h-[3rem] flex items-center justify-center select-none">
	{#if word}
		<span>{word}</span>
	{:else if blanks}
		<span class="mr-2">{blanks}</span>
		<span class="text-sm text-gray-600">({length} letters)</span>
	{:else}
		<span class="text-gray-400">&nbsp;</span>
	{/if}
</div>