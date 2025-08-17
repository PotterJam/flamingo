import { createSignal, createEffect, Component, Show, onMount } from 'solid-js';
import { actions, store } from '../store';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import { FaSolidPen } from 'solid-icons/fa';
import { translatePointerToCanvas } from '../lib/utils/canvas';
import { FiTrash2 } from 'solid-icons/fi';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from './Game';
import { ToggleGroup, ToggleGroupItem } from './ui/toggle-group';
import { RiDesignPaintFill } from 'solid-icons/ri';
import { clear, drawBetween, fill } from '~/lib/canvas';

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

interface Point {
    x: number;
    y: number;
}

interface WhiteboardProps {
    width: number;
    height: number;
}

const defaultBrushThickness = 9;

function canvasEffect(
    canvasCtx: CanvasRenderingContext2D,
    func: (imageData: ImageData) => void
) {
    const imageData = canvasCtx.getImageData(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
    func(imageData);
    canvasCtx.putImageData(imageData, 0, 0);
}

const Whiteboard: Component<WhiteboardProps> = () => {
    let canvasRef!: HTMLCanvasElement;
    let canvasCtx!: CanvasRenderingContext2D;

    const [lastCoord, setLastCoord] = createSignal<Point | null>(null);
    const [isDrawing, setIsDrawing] = createSignal(false);

    onMount(() => {
        const ctx = canvasRef.getContext('2d', { willReadFrequently: true });
        if (ctx === null) {
            throw new Error('Null canvas context');
        }
        canvasCtx = ctx;

        // Canvas is empty by default so need to make it white
        canvasEffect(canvasCtx, (imageData) => clear(imageData));
    });

    const [selectedColour, setSelectedColour] =
        createSignal<PaletteColor>('#000000');
    const [selectedThickness, setSelectedThickness] = createSignal(
        defaultBrushThickness
    );
    const [tool, setTool] = createSignal<'pen' | 'fill'>('pen');

    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

    // This system relies on the websocket messages being processed synchronously.
    // If this changes we will need something like a queue system.
    createEffect(() => {
        const drawEvent = store.gameState.pendingDrawEvent;
        if (!drawEvent) return;
        actions.clearPendingDrawEvent();

        canvasEffect(canvasCtx, (imageData) => {
            if (drawEvent.eventType === 'clear') {
                clear(imageData);
                return;
            }

            if (drawEvent.eventType === 'undo') return;

            if (drawEvent.eventType === 'fill') {
                fill(
                    Math.round(drawEvent.x),
                    Math.round(drawEvent.y),
                    drawEvent.color,
                    imageData
                );
                return;
            }

            if (drawEvent.eventType === 'start') {
                drawBetween(
                    drawEvent.x,
                    drawEvent.y,
                    drawEvent.x,
                    drawEvent.y,
                    drawEvent.lineWidth,
                    drawEvent.color,
                    imageData
                );
                return;
            }

            drawBetween(
                drawEvent.startX,
                drawEvent.startY,
                drawEvent.endX,
                drawEvent.endY,
                drawEvent.lineWidth,
                drawEvent.color,
                imageData
            );
        });
    });

    const handlePointerDown = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef || !isDrawer()) return;

        if (tool() === 'fill') {
            const [x, y] = translatePointerToCanvas(e, canvasRef);

            canvasEffect(canvasCtx, (imageData) => {
                fill(Math.round(x), Math.round(y), selectedColour(), imageData);
            });

            actions.handleClientDraw({
                eventType: 'fill',
                x: x,
                y: y,
                color: selectedColour(),
            });
            return;
        }

        setIsDrawing(true);
        const [x, y] = translatePointerToCanvas(e, canvasRef);
        setLastCoord({ x, y });

        canvasEffect(canvasCtx, (imageData) => {
            drawBetween(
                x,
                y,
                x,
                y,
                selectedThickness(),
                selectedColour(),
                imageData
            );
        });

        actions.handleClientDraw({
            eventType: 'start',
            x: x,
            y: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        });
    };

    const handlePointerUp = (e: PointerEvent) => {
        e.preventDefault();
        if (!isDrawer() || tool() === 'fill') return;

        setIsDrawing(false);

        const [x, y] = translatePointerToCanvas(e, canvasRef);
        const prev = lastCoord();
        setLastCoord(null);

        canvasEffect(canvasCtx, (imageData) => {
            drawBetween(
                prev?.x ?? x,
                prev?.y ?? y,
                x,
                y,
                selectedThickness(),
                selectedColour(),
                imageData
            );
        });

        actions.handleClientDraw({
            eventType: 'end',
            startX: prev?.x ?? x,
            startY: prev?.y ?? y,
            endX: x,
            endY: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        });
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
        if (tool() === 'fill') return;
        e.preventDefault();

        const [x, y] = translatePointerToCanvas(e, canvasRef);
        const prev = lastCoord();
        setLastCoord({ x, y });

        canvasEffect(canvasCtx, (imageData) => {
            drawBetween(
                prev?.x ?? x,
                prev?.y ?? y,
                x,
                y,
                selectedThickness(),
                selectedColour(),
                imageData
            );
        });

        actions.handleClientDraw({
            eventType: 'draw',
            startX: prev?.x ?? x,
            startY: prev?.y ?? y,
            endX: x,
            endY: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        });
    };

    const handleClear = () => {
        canvasEffect(canvasCtx, (imageData) => clear(imageData));
        store.sendMessage({
            type: 'drawEvent',
            payload: {
                eventType: 'clear',
            },
        });
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
                        {[6, 9, 15].map((thickness) => (
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
                    <div class="flex flex-row items-center gap-2 space-x-2 p-2">
                        {/* <button */}
                        {/*     class="p-1" */}
                        {/*     onClick={() => { */}
                        {/*         const undoEvent = { */}
                        {/*             eventType: 'undo' as const, */}
                        {/*         }; */}
                        {/**/}
                        {/*         actions.handleClientDraw(undoEvent); */}
                        {/*     }} */}
                        {/* > */}
                        {/*     <FaSolidArrowRotateLeft /> */}
                        {/* </button> */}
                        <button class="p-1" onClick={handleClear}>
                            <FiTrash2 />
                        </button>
                        <ToggleGroup value={tool()} onChange={setTool}>
                            <ToggleGroupItem value="pen">
                                <FaSolidPen />
                            </ToggleGroupItem>
                            <ToggleGroupItem value="fill">
                                <RiDesignPaintFill />
                            </ToggleGroupItem>
                        </ToggleGroup>
                    </div>
                </div>
            </Show>
        </div>
    );
};

export default Whiteboard;
