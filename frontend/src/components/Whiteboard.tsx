import { onMount } from 'solid-js';

export function Whiteboard() {
    let canvasRef: HTMLCanvasElement | undefined;

    onMount(() => {
        if (canvasRef) {
            const ctx = canvasRef.getContext('2d');
            if (ctx) {
                ctx.fillStyle = 'white';
                ctx.fillRect(0, 0, canvasRef.width, canvasRef.height);
            }
        }
    });

    return (
        <div class="flex justify-center">
            <canvas
                ref={canvasRef!}
                width={800}
                height={600}
                class="border border-gray-300 bg-white"
            />
        </div>
    );
}
