<script>
	// --- Props ---
	// The message string to display. Passed from App.svelte.
	export let message = '';
</script>

<div class="text-base lg:text-lg text-gray-700 min-h-[1.5rem] text-center transition-all duration-200">
	{message || '&nbsp;'}
</div>