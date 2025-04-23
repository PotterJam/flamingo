<script>
    import { onMount, createEventDispatcher, onDestroy } from "svelte";

    // --- Props ---
    // Determines if the current user can draw on the canvas. Passed from App.svelte.
    export let isDrawer = false;

    // --- Event Dispatcher ---
    // Used to send events ('draw', potentially 'clear') up to the parent (App.svelte).
    const dispatch = createEventDispatcher();

    // --- Canvas State ---
    let canvasElement; // The <canvas> DOM element
    let ctx; // The 2D rendering context
    let drawing = false; // Is the local user currently drawing (mouse/touch down)?
    let lastX = 0; // Last X position for local drawing lines
    let lastY = 0; // Last Y position for local drawing lines
    let remoteDrawing = false; // Is the remote player currently drawing? (for guesser)
    let remoteLastX = 0; // Last X position for remote drawing lines
    let remoteLastY = 0; // Last Y position for remote drawing lines

    // --- Drawing Configuration ---
    // These could be made dynamic with UI controls (color picker, slider)
    let strokeColor = "#000000"; // Default drawing color
    let lineWidth = 3; // Default line width

    // --- Lifecycle ---
    onMount(() => {
        // Get the 2D context once the component is mounted and the canvas element exists
        ctx = canvasElement.getContext("2d");
        // Set initial canvas size based on its container
        resizeCanvas();
        // Add event listener to handle window resizing
        window.addEventListener("resize", resizeCanvas);

        // Set default line styles
        ctx.lineCap = "round"; // Makes line endings rounded
        ctx.lineJoin = "round"; // Makes line connections rounded

        // Clear the canvas with a white background initially
        clearCanvasLocal();

        // Cleanup function: Remove the resize listener when the component is destroyed
        return () => {
            window.removeEventListener("resize", resizeCanvas);
        };
    });

    // --- Canvas Resizing ---

    /**
     * Resizes the canvas element to fit its parent container while attempting
     * to maintain aspect ratio and redraw existing content.
     */
    function resizeCanvas() {
        const parent = canvasElement.parentElement;
        // Ensure parent and context are available
        if (!parent || !ctx) {
            console.warn("Canvas parent or context not available for resize.");
            return;
        }

        // Get the available width from the parent container
        const { width } = parent.getBoundingClientRect();
        // Calculate height to maintain a 16:9 aspect ratio (adjust as needed)
        const height = (width * 9) / 16;

        // --- Content Preservation (Simple Method) ---
        // Store the current canvas content as an ImageData object before resizing.
        // Note: For very complex drawings, this can be inefficient.
        // More advanced methods involve drawing to an offscreen canvas or replaying draw events.
        let imageData = null;
        try {
            // Check if canvas has non-zero dimensions before getting image data
            if (canvasElement.width > 0 && canvasElement.height > 0) {
                imageData = ctx.getImageData(
                    0,
                    0,
                    canvasElement.width,
                    canvasElement.height,
                );
            }
        } catch (e) {
            console.error("Error getting canvas image data:", e);
            // This can happen due to security restrictions (tainted canvas) if external images were used.
        }

        // Set the new dimensions for the canvas element (this clears the canvas)
        canvasElement.width = width;
        canvasElement.height = height;

        // --- Restore Context Settings & Content ---
        // Resizing resets context properties, so reapply them.
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        // It's good practice to also restore other settings if they might change (lineWidth, strokeStyle)
        ctx.lineWidth = lineWidth;
        ctx.strokeStyle = strokeColor;

        // Restore the saved drawing onto the resized canvas.
        if (imageData) {
            // Create a temporary canvas to hold the old image data without scaling issues.
            const tempCanvas = document.createElement("canvas");
            tempCanvas.width = imageData.width;
            tempCanvas.height = imageData.height;
            const tempCtx = tempCanvas.getContext("2d");
            tempCtx.putImageData(imageData, 0, 0);

            // Draw the content from the temporary canvas onto the main (resized) canvas.
            // This scales the old content to fit the new dimensions.
            ctx.drawImage(
                tempCanvas,
                0,
                0,
                canvasElement.width,
                canvasElement.height,
            );
        } else {
            // If no previous image data, just clear the resized canvas.
            clearCanvasLocal();
        }
    }

    // --- Local Drawing Logic (Triggered by User Input) ---

    /**
     * Gets the mouse or touch coordinates relative to the canvas element.
     * @param {MouseEvent | TouchEvent} evt - The input event.
     * @returns {{x: number, y: number}} Coordinates relative to the canvas.
     */
    function getEventPos(evt) {
        const rect = canvasElement.getBoundingClientRect();
        // Handle both mouse and touch events
        // @ts-ignore
        const clientX = evt.touches ? evt.touches[0].clientX : evt.clientX;
        // @ts-ignore
        const clientY = evt.touches ? evt.touches[0].clientY : evt.clientY;
        return {
            x: clientX - rect.left,
            y: clientY - rect.top,
        };
    }

    /**
     * Handles mousedown / touchstart events to begin drawing.
     * @param {MouseEvent | TouchEvent} e - The input event.
     */
    function startDrawing(e) {
        // Only allow drawing if the user is designated as the drawer
        if (!isDrawer) return;
        drawing = true; // Set drawing flag
        const pos = getEventPos(e);
        [lastX, lastY] = [pos.x, pos.y]; // Record starting position

        // Optional: Draw a single dot at the start point immediately for responsiveness
        // drawLineLocal(ctx, lastX, lastY, pos.x, pos.y, strokeColor, lineWidth);

        // Dispatch a 'draw' event to App.svelte with 'start' type and details
        dispatch("draw", {
            eventType: "start",
            x: pos.x,
            y: pos.y,
            color: strokeColor,
            lineWidth: lineWidth,
        });
        e.preventDefault(); // Prevent default browser actions (e.g., page scrolling on touch)
    }

    /**
     * Handles mousemove / touchmove events to draw lines.
     * @param {MouseEvent | TouchEvent} e - The input event.
     */
    function draw(e) {
        // Only draw if allowed and currently drawing (mouse/touch is down)
        if (!isDrawer || !drawing) return;
        const pos = getEventPos(e);
        // Draw the line segment on the local canvas
        drawLineLocal(ctx, lastX, lastY, pos.x, pos.y, strokeColor, lineWidth);

        // Dispatch a 'draw' event to App.svelte with 'draw' type and details
        dispatch("draw", {
            eventType: "draw",
            x: pos.x,
            y: pos.y,
            color: strokeColor,
            lineWidth: lineWidth,
        });

        // Update the last position for the next segment
        [lastX, lastY] = [pos.x, pos.y];
        e.preventDefault(); // Prevent default browser actions
    }

    /**
     * Handles mouseup / mouseleave / touchend / touchcancel events to stop drawing.
     */
    function stopDrawing() {
        // Only stop if allowed and was actually drawing
        if (!isDrawer || !drawing) return;
        drawing = false; // Clear drawing flag
        // Dispatch a 'draw' event to App.svelte with 'end' type
        dispatch("draw", { eventType: "end" });
    }

    // --- Remote Drawing Logic (Triggered by WebSocket Events via App.svelte) ---

    /**
     * Public method called by App.svelte to handle drawing events received from the server.
     * Draws on the canvas if the current user is the guesser.
     * @param {object} payload - The draw event payload from the server.
     */
    export function handleDrawEvent(payload) {
        // Ignore if the current user is the drawer or if context isn't ready
        if (isDrawer || !ctx) return;

        // Extract drawing parameters from the payload, using defaults if necessary
        const eventStrokeColor = payload.color || "#000000";
        const eventLineWidth = payload.lineWidth || 3;

        // Process based on the event type
        if (payload.eventType === "start") {
            remoteDrawing = true; // Set remote drawing flag
            [remoteLastX, remoteLastY] = [payload.x, payload.y]; // Record remote start position
            // Optional: Draw a dot at the remote start position
            // drawLineLocal(ctx, remoteLastX, remoteLastY, payload.x, payload.y, eventStrokeColor, eventLineWidth);
        } else if (payload.eventType === "draw" && remoteDrawing) {
            // Draw the line segment based on remote data
            drawLineLocal(
                ctx,
                remoteLastX,
                remoteLastY,
                payload.x,
                payload.y,
                eventStrokeColor,
                eventLineWidth,
            );
            [remoteLastX, remoteLastY] = [payload.x, payload.y]; // Update remote last position
        } else if (payload.eventType === "end") {
            remoteDrawing = false; // Clear remote drawing flag
        }
    }

    // --- Canvas Utility Functions ---

    /**
     * Draws a single line segment on the provided canvas context.
     * @param {CanvasRenderingContext2D} context - The canvas context to draw on.
     * @param {number} x1 - Starting X coordinate.
     * @param {number} y1 - Starting Y coordinate.
     * @param {number} x2 - Ending X coordinate.
     * @param {number} y2 - Ending Y coordinate.
     * @param {string} color - Stroke color for the line.
     * @param {number} width - Line width.
     */
    function drawLineLocal(context, x1, y1, x2, y2, color, width) {
        if (!context) return;
        context.beginPath(); // Start a new path
        context.strokeStyle = color; // Set line color
        context.lineWidth = width; // Set line width
        // lineCap and lineJoin are set during onMount/resize
        context.moveTo(x1, y1); // Move to starting point
        context.lineTo(x2, y2); // Draw line to ending point
        context.stroke(); // Render the line
        context.closePath(); // Close the path
    }

    /**
     * Clears the entire canvas and fills it with a white background.
     */
    function clearCanvasLocal() {
        if (!ctx) return;
        ctx.fillStyle = "#FFFFFF"; // Set fill color to white
        // Fill the entire canvas area
        ctx.fillRect(0, 0, canvasElement.width, canvasElement.height);
    }

    /**
     * Public method to clear the canvas locally.
     * Can be called by App.svelte (e.g., if a clear button is added).
     * To clear for both players, the drawer would need to trigger a 'clearCanvas' WebSocket message.
     */
    export function clearCanvas() {
        clearCanvasLocal();
        // If the drawer clears, they might need to notify the server/other player
        // if (isDrawer) {
        //   dispatch('clear'); // Example: Dispatch event for App.svelte to handle
        // }
    }
</script>

<canvas
    bind:this={canvasElement}
    class="w-full h-full block bg-white cursor-crosshair"
    on:mousedown={startDrawing}
    on:mousemove={draw}
    on:mouseup={stopDrawing}
    on:mouseleave={stopDrawing}
    on:touchstart={startDrawing}
    on:touchmove={draw}
    on:touchend={stopDrawing}
    on:touchcancel={stopDrawing}
>
    Your browser does not support the HTML canvas element.
</canvas>
