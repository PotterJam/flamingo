import { PathPoint } from "~/components/Whiteboard";

export const translatePointerToCanvas = (
    e: PointerEvent,
    canvas: HTMLCanvasElement
): PathPoint => {
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    return [
        (e.clientX - rect.left) * scaleX,
        (e.clientY - rect.top) * scaleY,
        e.pressure,
    ];
};
