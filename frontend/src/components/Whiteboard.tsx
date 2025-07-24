import { createSignal, Component, createMemo, For, Show } from 'solid-js';
import { actions, store } from '../store';
import { DrawEvent } from '../messages';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import { getStroke } from 'perfect-freehand';
import { FaSolidArrowRotateLeft } from 'solid-icons/fa';
import {
    getSvgPathFromStroke,
    translatePointerToCanvas,
} from '../lib/utils/canvas';
import { render } from 'solid-js/web';

const PALETTE = {
    black: '#000000',
    white: '#FFFFFF',
    grey: '#C1C1C1',
    'dark-grey': '#505050',
    red: '#EF120B',
    'dark-red': '#740A08',
    orange: '#FF7700',
    'dark-orange': '#C23900',
    yellow: '#FFE404',
    'dark-yellow': '#E8A202',
    green: '#08C202',
    'dark-green': '#00461A',
    cyan: '#00FF91',
    'dark-cyan': '#02569E',
    blue: '#2220D3',
    'dark-blue': '#0E0865',
    purple: '#A302BA',
    'dark-purple': '#550069',
    pink: '#DF69A7',
    'dark-pink': '#883454',
    peach: '#FFAC8A',
    'dark-peach': '#CC7C4D',
    brown: '#A0522D',
    'dark-brown': '#63300D',
} as const;

interface WhiteboardProps {
    width: number;
    height: number;
}

// The format perfect-freehand expects: [x, y, pressure]
export type PathPoint = [number, number, number];

export interface Path {
    points: PathPoint[];
    colour: keyof typeof PALETTE;
}

const defaultBrushThickness = 9;

const sendDrawEvent = (drawEvent: DrawEvent) => {
    store.sendMessage({
        type: 'drawEvent',
        payload: drawEvent,
    });
};

const Whiteboard: Component<WhiteboardProps> = ({ height, width }) => {
    let canvasRef: SVGSVGElement | undefined;
    let ctxRef: CanvasRenderingContext2D | null = null;

    const [selectedColour, setSelectedColour] =
        createSignal<keyof typeof PALETTE>('black');
    const [selectedThickness, setSelectedThickness] = createSignal(
        defaultBrushThickness
    );

    const [isDrawing, setIsDrawing] = createSignal(false);
    const [finishedPaths, setFinishedPaths] = createSignal<Path[]>([]);
    const [currentPath, setCurrentPath] = createSignal<PathPoint[]>([]);

    // handleDraw({
    //     eventType: 'draw',
    //     x: pos.x,
    //     y: pos.y,
    //     color: PALETTE[selectedColour()],
    //     lineWidth: selectedThickness(),
    // });

    // handleDraw({ eventType: 'end' });

    // handleDraw({
    //     eventType: 'start',
    //     x: pos.x,
    //     y: pos.y,
    //     color: PALETTE[selectedColour()],
    //     lineWidth: selectedThickness(),
    // });

    const lastDrawEvent = () => store.gameState.lastDrawEvent;
    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

    let remoteCurrentStroke: Array<Path> = [];
    let remoteStrokeColor = '#000000';
    let remoteStrokeSize = 3;

    const handlePointerDown = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef) return;
        setIsDrawing(true);
        setCurrentPath([translatePointerToCanvas(e, canvasRef)]);
    };

    const handlePointerUp = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef) return;
        setIsDrawing(false);

        if (!currentPath()) return;

        setFinishedPaths((prev) => [
            ...prev,
            { points: currentPath(), colour: selectedColour() },
        ]);
        setCurrentPath([]);
    };

    const handlePointerLeave = (e: PointerEvent) => {
        if (!isDrawing()) return;
        if (!canvasRef) return;
        handlePointerUp(e);
    };

    const handlePointerEnter = (e: PointerEvent) => {
        if (e.buttons === 1) {
            handlePointerDown(e);
        }
    };

    const handlePointerMove = (e: PointerEvent) => {
        if (!isDrawing()) return;
        if (!canvasRef) return;
        e.preventDefault();

        setCurrentPath((prev) => [
            ...prev,
            translatePointerToCanvas(e, canvasRef),
        ]);
    };

    const renderedFinishedPaths = createMemo(() => {
        return finishedPaths().map((path) => ({
            colour: path.colour,
            points: getSvgPathFromStroke(getStroke(path.points)),
        }));
    });

    const renderedCurrentPath = createMemo(() => {
        if (!currentPath()) return null;
        return getSvgPathFromStroke(getStroke(currentPath()));
    });

    return (
        <div class="flex flex-col">
            <svg
                ref={canvasRef}
                class="block bg-white"
                style={{
                    width: `${width}px`,
                    height: `${height}px`,
                }}
                onPointerDown={handlePointerDown}
                onPointerMove={handlePointerMove}
                onPointerUp={handlePointerUp}
                onPointerLeave={handlePointerLeave}
                onPointerEnter={handlePointerEnter}
            >
                <For each={renderedFinishedPaths()}>
                    {(path) => <path d={path.points} fill={PALETTE[path.colour]} />}
                </For>
                <Show when={renderedCurrentPath()}>
                    {(path) => <path d={path()} fill={PALETTE[selectedColour()]} />}
                </Show>
            </svg>
            <Separator />
            <div class="flex w-full flex-row justify-between gap-2 p-2">
                <div class="my-2 h-12 w-12 border-2 border-gray-500 border-t-gray-300 border-l-gray-300">
                    <div
                        class="h-full w-full border-2 border-gray-300 border-t-gray-100 border-l-gray-300"
                        style={{
                            'background-color': PALETTE[selectedColour()],
                        }}
                    />
                </div>
                <div class="grid h-14 grid-cols-12 grid-rows-2 items-center justify-center">
                    {Object.entries(PALETTE).map(([colour, hex]) => (
                        <div
                            class="h-7 w-7 cursor-pointer transition-transform duration-150 ease-in-out hover:scale-130"
                            style={{ 'background-color': hex }}
                            onClick={() =>
                                setSelectedColour(
                                    colour as keyof typeof PALETTE
                                )
                            }
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
                        onClick={() =>
                            store.sendMessage({
                                type: 'drawPathUndo',
                                payload: {},
                            })
                        }
                    >
                        <FaSolidArrowRotateLeft></FaSolidArrowRotateLeft>
                    </button>
                </div>
            </div>
        </div>
    );
};

export default Whiteboard;
