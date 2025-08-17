import { createSignal, createEffect, Component, Show, onMount } from 'solid-js';
import { actions, store } from '../store';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import { FaSolidArrowRotateLeft, FaSolidPen } from 'solid-icons/fa';
import { translatePointerToCanvas } from '../lib/utils/canvas';
import { FiTrash2 } from 'solid-icons/fi';
import { CANVAS_HEIGHT, CANVAS_WIDTH } from './Game';
import { ToggleGroup, ToggleGroupItem } from './ui/toggle-group';
import { RiDesignPaintFill } from 'solid-icons/ri';
import { clear, drawBetween, fill } from '~/lib/canvas';
import { DrawEvent } from '~/messages';

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
    '#04785E',
    '#00B2FF',
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

function handleEvent(imageData: ImageData, drawEvent: DrawEvent) {
    switch (drawEvent.eventType) {
        case 'clear':
            clear(imageData);
            break;
        case 'undo':
            break;
        case 'fill':
            fill(
                Math.round(drawEvent.x),
                Math.round(drawEvent.y),
                drawEvent.color,
                imageData
            );
            break;
        case 'start':
            drawBetween(
                drawEvent.x,
                drawEvent.y,
                drawEvent.x,
                drawEvent.y,
                drawEvent.lineWidth,
                drawEvent.color,
                imageData
            );
            break;
        case 'draw':
        case 'end':
            drawBetween(
                drawEvent.startX,
                drawEvent.startY,
                drawEvent.endX,
                drawEvent.endY,
                drawEvent.lineWidth,
                drawEvent.color,
                imageData
            );
            break;
    }
}

export const Whiteboard: Component<WhiteboardProps> = () => {
    let canvasRef!: HTMLCanvasElement;
    let canvasCtx!: CanvasRenderingContext2D;

    const [lastCoord, setLastCoord] = createSignal<Point | null>(null);
    const [isDrawing, setIsDrawing] = createSignal(false);
    const [selectedColour, setSelectedColour] =
        createSignal<PaletteColor>('#000000');
    const [selectedThickness, setSelectedThickness] = createSignal(
        defaultBrushThickness
    );
    const [tool, setTool] = createSignal<'pen' | 'fill'>('pen');
    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

    onMount(() => {
        const ctx = canvasRef.getContext('2d', { willReadFrequently: true });
        if (ctx === null) throw new Error('Null canvas context');
        canvasCtx = ctx;
        canvasEffect(canvasCtx, (imageData) => clear(imageData));
    });

    // This system relies on the websocket messages being processed synchronously.
    // If this changes we will need something like a queue system.
    createEffect(() => {
        const drawEvent = store.gameState.pendingDrawEvent;
        if (!drawEvent) return;
        actions.clearPendingDrawEvent();

        if (drawEvent.eventType !== 'undo') {
            canvasEffect(canvasCtx, (imageData) => {
                handleEvent(imageData, drawEvent);
            });
            return;
        }

        const events = store.gameState.drawEventsStack;
        canvasEffect(canvasCtx, (imageData) => {
            clear(imageData);
            for (const e of events) {
                handleEvent(imageData, e);
            }
        });
    });

    const handlePointerDown = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef || !isDrawer()) return;

        if (tool() === 'fill') {
            const [x, y] = translatePointerToCanvas(e, canvasRef);

            const fillEvent = {
                eventType: 'fill' as const,
                x: x,
                y: y,
                color: selectedColour(),
            };
            canvasEffect(canvasCtx, (imageData) => {
                handleEvent(imageData, fillEvent);
            });
            actions.handleClientDraw(fillEvent);
            return;
        }

        setIsDrawing(true);
        const [x, y] = translatePointerToCanvas(e, canvasRef);
        setLastCoord({ x, y });

        const startEvent = {
            eventType: 'start' as const,
            x: x,
            y: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        };
        canvasEffect(canvasCtx, (imageData) => {
            handleEvent(imageData, startEvent);
        });
        actions.handleClientDraw(startEvent);
    };

    const handlePointerUp = (e: PointerEvent) => {
        e.preventDefault();
        if (!isDrawer() || tool() === 'fill') return;

        setIsDrawing(false);

        const [x, y] = translatePointerToCanvas(e, canvasRef);
        const prev = lastCoord();
        setLastCoord(null);

        const endEvent = {
            eventType: 'end' as const,
            startX: prev?.x ?? x,
            startY: prev?.y ?? y,
            endX: x,
            endY: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        };
        canvasEffect(canvasCtx, (imageData) => {
            handleEvent(imageData, endEvent);
        });
        actions.handleClientDraw(endEvent);
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

        const drawEvent = {
            eventType: 'draw' as const,
            startX: prev?.x ?? x,
            startY: prev?.y ?? y,
            endX: x,
            endY: y,
            color: selectedColour(),
            lineWidth: selectedThickness(),
        };
        canvasEffect(canvasCtx, (imageData) => {
            handleEvent(imageData, drawEvent);
        });
        actions.handleClientDraw(drawEvent);
    };

    const handleClear = () => {
        const clearEvent = { eventType: 'clear' as const };

        canvasEffect(canvasCtx, (imageData) => {
            handleEvent(imageData, clearEvent);
        });

        store.sendMessage({
            type: 'drawEvent',
            payload: clearEvent,
        });
    };

    const handleUndo = () => {
        actions.handleClientDraw({
            eventType: 'undo',
        });

        const events = store.gameState.drawEventsStack;
        canvasEffect(canvasCtx, (imageData) => {
            clear(imageData);
            for (const e of events) {
                handleEvent(imageData, e);
            }
        });
    };

    return (
        <div class="flex flex-col">
            <canvas
                width={CANVAS_WIDTH}
                height={CANVAS_HEIGHT}
                ref={canvasRef}
                class={isDrawer() ? 'cursor-crosshair' : ''}
                onPointerEnter={handlePointerEnter}
                onPointerUp={handlePointerUp}
                onPointerMove={handlePointerMove}
                onPointerLeave={handlePointerLeave}
                onPointerDown={handlePointerDown}
            />
            <Separator />
            <Show when={isDrawer()}>
                <div class="flex w-full flex-row justify-between gap-2 p-2">
                    <div class="border-border box-content grid h-14 w-91 grid-flow-col grid-cols-12 grid-rows-2 items-center justify-center border-2">
                        {PALETTE.map((hex) => (
                            <div
                                class="h-7 w-7 cursor-pointer"
                                style={{ 'background-color': hex }}
                                onClick={() => setSelectedColour(hex)}
                            >
                                {selectedColour() === hex && (
                                    <div class="h-full w-full border-2 border-white">
                                        <div class="border-border h-full w-full border-2" />
                                    </div>
                                )}
                            </div>
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
                        <button class="p-1" onClick={handleUndo}>
                            <FaSolidArrowRotateLeft />
                        </button>
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
