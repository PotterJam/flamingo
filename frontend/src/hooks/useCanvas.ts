interface UseCanvasProps {
    canvasCtx: CanvasRenderingContext2D;
}

export const useCanvas = ({ canvasCtx }: UseCanvasProps) => {
    const drawAtCoord = (
        centerX: number,
        centerY: number,
        thickness: number,
        hexColor: string
    ) => {
        const radius = thickness / 2;
        const x = Math.round(centerX);
        const y = Math.round(centerY);

        canvasCtx.fillStyle = hexColor;
        canvasCtx.beginPath();
        canvasCtx.arc(x, y, radius, 0, 2 * Math.PI);
        canvasCtx.fill();
    };

    const drawBetween = (
        startX: number,
        startY: number,
        endX: number,
        endY: number,
        thickness: number,
        hexColor: string
    ) => {
        const dx = endX - startX;
        const dy = endY - startY;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const steps = Math.max(Math.ceil(distance), 1);

        for (let i = 0; i <= steps; i++) {
            const t = i / steps; // Linear interpolation
            const x = Math.round(startX + dx * t);
            const y = Math.round(startY + dy * t);

            drawAtCoord(x, y, thickness, hexColor);
        }
    };

    return {
        drawBetween,
    };
};

