import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../components/Game';
import { Point } from '../model';

interface UseCanvasProps {
    canvasCtx: CanvasRenderingContext2D;
}

export const useCanvas = ({ canvasCtx }: UseCanvasProps) => {
    const hexToRgb = (hex: string): [number, number, number] => {
        const r = parseInt(hex.substring(1, 3), 16);
        const g = parseInt(hex.substring(3, 5), 16);
        const b = parseInt(hex.substring(5, 7), 16);
        return [r, g, b];
    };

    const drawAtCoord = (
        centerX: number,
        centerY: number,
        thickness: number,
        hexColour: string
    ) => {
        const radius = Math.round(thickness / 2);
        const centerXRound = Math.round(centerX);
        const centerYRound = Math.round(centerY);
        const fillRgb = hexToRgb(hexColour);

        const imageData = canvasCtx.getImageData(
            0,
            0,
            CANVAS_WIDTH,
            CANVAS_HEIGHT
        );
        const data = imageData.data;

        for (let x = centerXRound - radius; x <= centerXRound + radius; x++) {
            for (
                let y = centerYRound - radius;
                y <= centerYRound + radius;
                y++
            ) {
                if (x >= 0 && x < CANVAS_WIDTH && y >= 0 && y < CANVAS_HEIGHT) {
                    const distance = Math.sqrt(
                        (x - centerXRound) ** 2 + (y - centerYRound) ** 2
                    );

                    if (distance < radius) {
                        const index = (y * CANVAS_WIDTH + x) * 4;
                        data[index] = fillRgb[0];
                        data[index + 1] = fillRgb[1];
                        data[index + 2] = fillRgb[2];
                        data[index + 3] = 255;
                    }
                }
            }
        }

        canvasCtx.putImageData(imageData, 0, 0);
    };

    const drawBetween = (
        startX: number,
        startY: number,
        endX: number,
        endY: number,
        thickness: number,
        hexColour: string
    ) => {
        if (startX === endX && startY === endY)
            drawAtCoord(startX, startY, thickness, hexColour);

        const dx = endX - startX;
        const dy = endY - startY;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const steps = Math.max(Math.ceil(distance), 1);

        for (let i = 0; i <= steps; i++) {
            const t = i / steps; // Linear interpolation
            const x = Math.round(startX + dx * t);
            const y = Math.round(startY + dy * t);

            drawAtCoord(x, y, thickness, hexColour);
        }
    };

    const fill = (rootX: number, rootY: number, colour: string) => {
        const fillRgb = hexToRgb(colour);

        const image = canvasCtx.getImageData(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);

        const rootIndex = (rootY * CANVAS_WIDTH + rootX) * 4;
        const originalColor = [
            image.data[rootIndex],
            image.data[rootIndex + 1],
            image.data[rootIndex + 2],
        ];

        const stack: Point[] = [];
        stack.push({ x: rootX, y: rootY });

        const visited = new Set([{ x: rootX, y: rootY }]);

        while (stack.length > 0) {
            const { x, y } = stack.pop()!;
            visited.add({ x, y });

            if (x >= CANVAS_WIDTH || y >= CANVAS_HEIGHT || x < 0 || y < 0)
                continue;

            if (visited.has({ x, y })) continue;

            const index = (y * CANVAS_WIDTH + x) * 4;
            const currentColor = [
                image.data[index],
                image.data[index + 1],
                image.data[index + 2],
            ];

            if (
                currentColor[0] !== originalColor[0] ||
                currentColor[1] !== originalColor[1] ||
                currentColor[2] !== originalColor[2]
            ) {
                continue;
            }

            image.data[index] = fillRgb[0];
            image.data[index + 1] = fillRgb[1];
            image.data[index + 2] = fillRgb[2];
            image.data[index + 3] = 255;

            stack.push({ x: x, y: y + 1 });
            stack.push({ x: x, y: y - 1 });
            stack.push({ x: x + 1, y: y });
            stack.push({ x: x - 1, y: y });
        }

        canvasCtx.putImageData(image, 0, 0);
    };

    return {
        drawBetween,
        fill,
    };
};
