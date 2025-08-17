import { CANVAS_HEIGHT, CANVAS_WIDTH } from '../components/Game';
import { Point } from '../model';

const hexToRgb = (hex: string): [number, number, number] => {
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    return [r, g, b];
};

export const clear = (canvasCtx: CanvasRenderingContext2D) => {
    canvasCtx.fillStyle = '#ffffff';
    canvasCtx.fillRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
};

export const drawBetween = (
    startX: number,
    startY: number,
    endX: number,
    endY: number,
    thickness: number,
    hexColour: string,
    imageData: ImageData
) => {
    const radius = thickness / 2;
    const fillRgb = hexToRgb(hexColour);

    const data = imageData.data;

    // This algo is generally called Line Segment SDF and uses the "distance to line segment"
    // Create the smallest possible bounding rectangle that contains the line
    // We only need to consider points inside this region rather than the whole canvas
    // We add radius onto the max and min to support rounding the ends of the line
    const minX = Math.max(0, Math.floor(Math.min(startX, endX) - radius));
    const maxX = Math.min(
        CANVAS_WIDTH - 1,
        Math.ceil(Math.max(startX, endX) + radius)
    );
    const minY = Math.max(0, Math.floor(Math.min(startY, endY) - radius));
    const maxY = Math.min(
        CANVAS_HEIGHT - 1,
        Math.ceil(Math.max(startY, endY) + radius)
    );

    const dx = endX - startX;
    const dy = endY - startY;
    const lineLength = Math.sqrt(dx * dx + dy * dy);

    for (let x = minX; x <= maxX; x++) {
        for (let y = minY; y <= maxY; y++) {
            let distance;

            // We want to work out the distance between the point in question in the rectangle
            // and its projected point along the line
            if (lineLength === 0) {
                distance = Math.sqrt((x - startX) ** 2 + (y - startY) ** 2);
            } else {
                // t is how far along the line we are, so 0.2 = 20% of the way from min to max
                const t = Math.max(
                    0,
                    Math.min(
                        1,
                        ((x - startX) * dx + (y - startY) * dy) /
                            (lineLength * lineLength)
                    )
                );
                const projX = startX + t * dx;
                const projY = startY + t * dy;
                distance = Math.sqrt((x - projX) ** 2 + (y - projY) ** 2);
            }

            // Only fill things where the distance to the line is within the desired radius
            if (distance <= radius) {
                const index = (y * CANVAS_WIDTH + x) * 4;
                data[index] = fillRgb[0];
                data[index + 1] = fillRgb[1];
                data[index + 2] = fillRgb[2];
                data[index + 3] = 255;
            }
        }
    }
};

export const fill = (
    rootX: number,
    rootY: number,
    colour: string,
    imageData: ImageData
) => {
    const data = imageData.data;
    const fillRgb = hexToRgb(colour);

    const rootIndex = (rootY * CANVAS_WIDTH + rootX) * 4;
    const originalColor = [
        data[rootIndex],
        data[rootIndex + 1],
        data[rootIndex + 2],
    ];

    const visited = new Array(CANVAS_WIDTH * CANVAS_HEIGHT).fill(false);
    const stack: Point[] = [];
    stack.push({ x: rootX, y: rootY });

    while (stack.length > 0) {
        const { x, y } = stack.pop()!;

        if (x < 0 || x >= CANVAS_WIDTH || y < 0 || y >= CANVAS_HEIGHT) {
            continue;
        }

        const index = (y * CANVAS_WIDTH + x) * 4;
        const currentColor = [data[index], data[index + 1], data[index + 2]];

        const pixelIndex = y * CANVAS_WIDTH + x;
        if (
            visited[pixelIndex] ||
            currentColor[0] !== originalColor[0] ||
            currentColor[1] !== originalColor[1] ||
            currentColor[2] !== originalColor[2]
        ) {
            continue;
        }

        visited[pixelIndex] = true;
        data[index] = fillRgb[0];
        data[index + 1] = fillRgb[1];
        data[index + 2] = fillRgb[2];
        data[index + 3] = 255;

        stack.push({ x: x, y: y + 1 });
        stack.push({ x: x, y: y - 1 });
        stack.push({ x: x + 1, y: y });
        stack.push({ x: x - 1, y: y });
    }
};
