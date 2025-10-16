import { createEffect, createSignal, onCleanup } from 'solid-js';
import { DrawEvent } from '../messages';
import { clear, drawBetween, fill } from '../lib/canvas';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from './Game';
import {
    Slider,
    SliderFill,
    SliderThumb,
    SliderTrack,
} from './ui/slider';

interface DrawingReplayProps {
    drawingSteps: DrawEvent[];
    playerName: string;
}

export const DrawingReplay = (props: DrawingReplayProps) => {
    const [sliderValue, setSliderValue] = createSignal([0]);
    let canvasRef: HTMLCanvasElement | undefined;

    const replayDrawing = (upToStep: number) => {
        if (!canvasRef) return;

        const ctx = canvasRef.getContext('2d', { willReadFrequently: true });
        if (!ctx) return;

        const imageData = ctx.createImageData(CANVAS_WIDTH, CANVAS_HEIGHT);
        clear(imageData);

        // Replay all steps up to the slider position
        for (let i = 0; i < upToStep && i < props.drawingSteps.length; i++) {
            const event = props.drawingSteps[i];

            if (event.eventType === 'clear') {
                clear(imageData);
            } else if (event.eventType === 'draw') {
                drawBetween(
                    event.startX,
                    event.startY,
                    event.endX,
                    event.endY,
                    event.lineWidth,
                    event.color,
                    imageData
                );
            } else if (event.eventType === 'start') {
                drawBetween(
                    event.x,
                    event.y,
                    event.x,
                    event.y,
                    event.lineWidth,
                    event.color,
                    imageData
                );
            } else if (event.eventType === 'fill') {
                fill(
                    Math.floor(event.x),
                    Math.floor(event.y),
                    event.color,
                    imageData
                );
            }
        }

        ctx.putImageData(imageData, 0, 0);
    };

    createEffect(() => {
        const step = sliderValue()[0];
        replayDrawing(step);
    });

    // Initialize with full drawing
    createEffect(() => {
        if (props.drawingSteps.length > 0) {
            setSliderValue([props.drawingSteps.length]);
        }
    });

    return (
        <div class="flex flex-col gap-2">
            <h3 class="text-center font-semibold text-gray-800">
                {props.playerName}
            </h3>
            <canvas
                ref={canvasRef}
                width={CANVAS_WIDTH}
                height={CANVAS_HEIGHT}
                class="border-2 border-black bg-white"
                style={{
                    width: '300px',
                    height: '214px',
                    'image-rendering': 'pixelated',
                }}
            />
            <div class="px-2">
                <Slider
                    value={sliderValue()}
                    onChange={setSliderValue}
                    minValue={0}
                    maxValue={props.drawingSteps.length}
                    step={1}
                    class="w-full"
                >
                    <SliderTrack>
                        <SliderFill />
                    </SliderTrack>
                    <SliderThumb />
                </Slider>
                <div class="mt-1 text-center text-xs text-gray-600">
                    {sliderValue()[0]} / {props.drawingSteps.length} steps
                </div>
            </div>
        </div>
    );
};
