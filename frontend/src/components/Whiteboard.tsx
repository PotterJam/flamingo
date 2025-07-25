import { createSignal, Component, createMemo, For, Show } from 'solid-js';
import { actions, store } from '../store';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import { getStroke, StrokeOptions } from 'perfect-freehand';
import { FaSolidArrowRotateLeft } from 'solid-icons/fa';
import {
    getSvgPathFromStroke,
    translatePointerToCanvas,
} from '../lib/utils/canvas';

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

const Whiteboard: Component<WhiteboardProps> = ({ height, width }) => {
    let canvasRef: SVGSVGElement | undefined;

    const [selectedColour, setSelectedColour] =
        createSignal<PaletteColor>('#000000');
    const [selectedThickness, setSelectedThickness] = createSignal(
        defaultBrushThickness
    );
    const [isDrawing, setIsDrawing] = createSignal(false);

    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

    const handlePointerDown = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef || !isDrawer()) return;
        setIsDrawing(true);
        actions.startPath(
            translatePointerToCanvas(e, canvasRef),
            selectedColour(),
            selectedThickness()
        );
    };

    const handlePointerUp = (e: PointerEvent) => {
        e.preventDefault();
        if (!canvasRef || !isDrawer()) return;
        setIsDrawing(false);
        actions.finishPath();
    };

    const handlePointerLeave = (e: PointerEvent) => {
        if (!isDrawing()) return;
        if (!canvasRef) return;
        handlePointerUp(e);
    };

    const handlePointerEnter = (e: PointerEvent) => {
        if (e.buttons === 1 && isDrawer()) {
            handlePointerDown(e);
        }
    };

    const handlePointerMove = (e: PointerEvent) => {
        if (!isDrawing() || !isDrawer()) return;
        if (!canvasRef) return;
        e.preventDefault();
        actions.continuePath(translatePointerToCanvas(e, canvasRef));
    };

    const renderedFinishedPaths = createMemo(() => {
        return store.whiteboardState.finishedPaths.map((path) => {
            const settings = {
                size: path.thickness,
            } as StrokeOptions;

            return {
                colour: path.colour,
                points: getSvgPathFromStroke(getStroke(path.points, settings)),
            };
        });
    });

    const renderedCurrentPath = createMemo(() => {
        if (
            !store.whiteboardState.currentPath ||
            !store.whiteboardState.currentPath.points.length
        )
            return null;

        const settings = {
            size: store.whiteboardState.currentPath.thickness,
        } as StrokeOptions;

        return getSvgPathFromStroke(
            getStroke(store.whiteboardState.currentPath.points, settings)
        );
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
                    {(path) => <path d={path.points} fill={path.colour} />}
                </For>
                <Show when={renderedCurrentPath()}>
                    {(path) => (
                        <path
                            d={path()}
                            fill={
                                store.whiteboardState.currentPath?.colour ||
                                selectedColour()
                            }
                        />
                    )}
                </Show>
            </svg>
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
            </Show>
        </div>
    );
};

export default Whiteboard;
