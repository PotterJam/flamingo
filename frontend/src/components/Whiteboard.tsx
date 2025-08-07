import { createSignal, createEffect, Component, Show, onMount } from 'solid-js';
import { actions, store } from '../store';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import {
    FaSolidArrowRotateLeft,
    FaSolidBucket,
    FaSolidPen,
} from 'solid-icons/fa';
import { translatePointerToCanvas } from '../lib/utils/canvas';
import { FiTrash2 } from 'solid-icons/fi';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from './Game';

const PALETTE = [
    '#000000',
    '#FFFFFF',
    '#C1C1C1',
    '#505050',
    '#EF120B',
    '#740A08',
    '#FF7700',
    '#C23900',
    '#FFE404',
    '#E8A202',
    '#08C202',
    '#00461A',
    '#00FF91',
    '#02569E',
    '#2220D3',
    '#0E0865',
    '#A302BA',
    '#550069',
    '#DF69A7',
    '#883454',
    '#FFAC8A',
    '#CC7C4D',
    '#A0522D',
    '#63300D',
] as const;

type PaletteColor = (typeof PALETTE)[number];

interface WhiteboardProps {
    width: number;
    height: number;
}

const defaultBrushThickness = 9;

interface Coord {
    x: number;
    y: number;
}

const Whiteboard: Component<WhiteboardProps> = () => {
    let canvasRef!: HTMLCanvasElement;
    let canvasCtx!: CanvasRenderingContext2D;

    const [lastCoord, setLastCoord] = createSignal<Coord | null>(null);

    onMount(() => {
        const ctx = canvasRef.getContext('2d');
        if (ctx === null) {
            throw new Error('Null canvas context');
        }
        canvasCtx = ctx;
    });

    const [selectedColour, setSelectedColour] =
        createSignal<PaletteColor>('#000000');
    const [selectedThickness, setSelectedThickness] = createSignal(
        defaultBrushThickness
    );
    const [isDrawing, setIsDrawing] = createSignal(false);
    const [isFill, setIsFill] = createSignal(false);

    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

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
            const t = i / steps; // Liner interpolation
            const x = Math.round(startX + dx * t);
            const y = Math.round(startY + dy * t);

            drawAtCoord(x, y, thickness, hexColor);
        }
    };

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

    // This system relies on the websocket messages being processed synchronously.
    // If this changes we will need something like a queue system.
    createEffect(() => {
        const drawEvent = store.gameState.pendingDrawEvent;
        if (!drawEvent) return;

        if (drawEvent.eventType === 'end') {
            setLastCoord(null);
            actions.clearPendingDrawEvent();
            return;
        }

        let prev = lastCoord();
        if (prev === null) {
            prev = { x: drawEvent.x, y: drawEvent.y };
        }

        drawBetween(
            prev.x,
            prev.y,
            drawEvent.x,
            drawEvent.y,
            drawEvent.lineWidth,
            drawEvent.color
        );

        setLastCoord({ x: drawEvent.x, y: drawEvent.y });

        actions.clearPendingDrawEvent();
    });

    const handlePointerDown = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef || !isDrawer()) return;

        if (isFill()) {
            const [x, y, _] = translatePointerToCanvas(e, canvasRef);
            store.sendMessage({
                type: 'fill',
                payload: {
                    x: x,
                    y: y,
                    color: selectedColour(),
                },
            });
            return;
        }

        setIsDrawing(true);

        const [x, y, p] = translatePointerToCanvas(e, canvasRef);
        drawBetween(x, y, x, y, selectedThickness(), selectedColour());
        setLastCoord({ x, y });
        actions.startPath([x, y, p], selectedColour(), selectedThickness());
    };

    const handlePointerUp = (e: PointerEvent) => {
        e.preventDefault();
        if (!isDrawer() || isFill()) return;

        setIsDrawing(false);

        const [x, y, _] = translatePointerToCanvas(e, canvasRef);
        const prev = lastCoord();
        drawBetween(
            prev?.x ?? x,
            prev?.y ?? y,
            x,
            y,
            selectedThickness(),
            selectedColour()
        );
        setLastCoord(null);
        actions.finishPath();
    };

    const handlePointerLeave = (e: PointerEvent) => {
        if (!isDrawing()) return;
        handlePointerUp(e);
    };

    const handlePointerEnter = (e: PointerEvent) => {
        if (e.buttons === 1 && isDrawer()) {
            handlePointerDown(e);
        }
    };

    const handlePointerMove = (e: PointerEvent) => {
        if (!isDrawing() || !isDrawer()) return;
        if (isFill()) return;
        e.preventDefault();

        const [x, y, _] = translatePointerToCanvas(e, canvasRef);
        const prev = lastCoord();
        drawBetween(
            prev?.x ?? x,
            prev?.y ?? y,
            x,
            y,
            selectedThickness(),
            selectedColour()
        );
        setLastCoord({ x, y });

        actions.continuePath(translatePointerToCanvas(e, canvasRef));
    };

    return (
        <div class="flex flex-col">
            <canvas
                width={CANVAS_WIDTH}
                height={CANVAS_HEIGHT}
                ref={canvasRef}
                onPointerEnter={handlePointerEnter}
                onPointerUp={handlePointerUp}
                onPointerMove={handlePointerMove}
                onPointerLeave={handlePointerLeave}
                onPointerDown={handlePointerDown}
            />
            <Separator />
            <Show when={isDrawer()}>
                <div class="flex w-full flex-row justify-between gap-2 p-2">
                    <div class="my-2 h-12 w-12 border-2 border-gray-500 border-t-gray-300 border-l-gray-300">
                        <div
                            class="h-full w-full border-2 border-gray-300 border-t-gray-100 border-l-gray-300"
                            style={{
                                'background-color': selectedColour(),
                            }}
                        />
                    </div>
                    <div class="grid h-14 grid-cols-12 grid-rows-2 items-center justify-center">
                        {PALETTE.map((hex) => (
                            <div
                                class="h-7 w-7 cursor-pointer transition-transform duration-150 ease-in-out hover:scale-130"
                                style={{ 'background-color': hex }}
                                onClick={() => setSelectedColour(hex)}
                            />
                        ))}
                    </div>
                    <div class="flex flex-row items-center space-x-2">
                        {[6, 9, 12].map((thickness) => (
                            <div
                                class={classNames(
                                    'flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-gray-400 bg-white hover:ring-2 hover:ring-blue-500',
                                    {
                                        'ring-2 ring-blue-500 ring-offset-1':
                                            selectedThickness() === thickness,
                                    }
                                )}
                                onClick={() => setSelectedThickness(thickness)}
                            >
                                <div
                                    class="rounded-full bg-black"
                                    style={{
                                        width: `${thickness * 2}px`,
                                        height: `${thickness * 2}px`,
                                    }}
                                />
                            </div>
                        ))}
                    </div>
                    <div class="flex flex-row items-center space-x-2 p-2">
                        <button
                            class="p-1"
                            onClick={() =>
                                store.sendMessage({
                                    type: 'drawPathUndo',
                                    payload: {},
                                })
                            }
                        >
                            <FaSolidArrowRotateLeft />
                        </button>
                        <button
                            class="p-1"
                            onClick={() =>
                                store.sendMessage({
                                    type: 'clearDrawing',
                                    payload: {},
                                })
                            }
                        >
                            <FiTrash2 />
                        </button>
                        <button
                            class="p-1"
                            onClick={() => setIsFill((prev) => !prev)}
                        >
                            <Show when={isFill()} fallback={<FaSolidBucket />}>
                                <FaSolidPen />
                            </Show>
                        </button>
                    </div>
                </div>
            </Show>
        </div>
    );
};

export default Whiteboard;
