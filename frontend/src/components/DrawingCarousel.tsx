import { createSignal, For, Show } from 'solid-js';
import { PlayerDrawingHistory } from '../store';
import { DrawingReplay } from './DrawingReplay';
import { Button } from './ui/button';

interface DrawingCarouselProps {
    drawings: PlayerDrawingHistory[];
    side: 'left' | 'right';
}

export const DrawingCarousel = (props: DrawingCarouselProps) => {
    const [currentIndex, setCurrentIndex] = createSignal(0);

    const hasDrawings = () => props.drawings.length > 0;
    const currentDrawing = () => props.drawings[currentIndex()];

    const nextDrawing = () => {
        setCurrentIndex((prev) => (prev + 1) % props.drawings.length);
    };

    const prevDrawing = () => {
        setCurrentIndex(
            (prev) => (prev - 1 + props.drawings.length) % props.drawings.length
        );
    };

    return (
        <div class="flex flex-col items-center gap-3">
            <Show when={hasDrawings()} fallback={<div class="text-gray-500">No drawings</div>}>
                <DrawingReplay
                    drawingSteps={currentDrawing().drawingSteps}
                    playerName={currentDrawing().playerName}
                />
                <Show when={props.drawings.length > 1}>
                    <div class="flex items-center gap-2">
                        <Button onClick={prevDrawing} variant="outline" size="sm">
                            ←
                        </Button>
                        <span class="text-sm text-gray-600">
                            {currentIndex() + 1} / {props.drawings.length}
                        </span>
                        <Button onClick={nextDrawing} variant="outline" size="sm">
                            →
                        </Button>
                    </div>
                </Show>
            </Show>
        </div>
    );
};
