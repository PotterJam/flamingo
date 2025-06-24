import { createSignal, createEffect, onCleanup, Component } from 'solid-js';
import { useAppStore, actions } from '../store';
import { DrawEvent } from '../messages';
import classNames from 'classnames';

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

const Whiteboard: Component<WhiteboardProps> = ({ height, width }) => {
    let canvasRef: HTMLCanvasElement | undefined;
    let ctxRef: CanvasRenderingContext2D | null = null;
    const [isDrawing, setIsDrawing] = createSignal(false);
    let lastPosRef = { x: 0, y: 0 };

    const [selectedColour, setSelectedColour] = createSignal<keyof typeof PALETTE>('black');
    const [selectedThickness, setSelectedThickness] = createSignal(3);

    const store = useAppStore();
    const lastDrawEvent = () => store.gameState.lastDrawEvent;
    const isDrawer = () => store.gameState.localPlayerId === store.gameState.currentDrawerId;

    let remoteLastPosRef = { x: 0, y: 0 };

    const handleDraw = (drawEvent: DrawEvent) => {
        store.sendMessage({
            type: 'drawEvent',
            payload: drawEvent,
        });
    };

    const getEventPos = (evt: any) => {
        if (!canvasRef) return null;
        const rect = canvasRef.getBoundingClientRect();

        const scaleX = canvasRef.width / rect.width;
        const scaleY = canvasRef.height / rect.height;
        return {
            x: (evt.clientX - rect.left) * scaleX,
            y: (evt.clientY - rect.top) * scaleY,
        };
    };

    const drawLine = (
        x1: number,
        y1: number,
        x2: number,
        y2: number,
        color: string,
        width: number
    ) => {
        if (!ctxRef) return;
        ctxRef.beginPath();
        ctxRef.strokeStyle = color;
        ctxRef.lineWidth = width;
        ctxRef.lineCap = 'round';
        ctxRef.lineJoin = 'round';
        ctxRef.moveTo(x1, y1);
        ctxRef.lineTo(x2, y2);
        ctxRef.stroke();
        ctxRef.closePath();
    };

    const globalMouseMove = (e: MouseEvent) => {
        if (!isDrawer() || !isDrawing()) return;
        const pos = getEventPos(e);
        if (!pos) return;
        drawLine(
            lastPosRef.x,
            lastPosRef.y,
            pos.x,
            pos.y,
            PALETTE[selectedColour()],
            selectedThickness()
        );
        handleDraw({
            eventType: 'draw',
            x: pos.x,
            y: pos.y,
            color: PALETTE[selectedColour()],
            lineWidth: selectedThickness(),
        });
        lastPosRef = pos;
        if (e.cancelable) e.preventDefault();
    };

    const globalMouseUp = () => {
        if (!isDrawer() || !isDrawing()) return;
        setIsDrawing(false);
        handleDraw({ eventType: 'end' });
        // Remove global event listeners
        document.removeEventListener('mousemove', globalMouseMove);
        document.removeEventListener('mouseup', globalMouseUp);
    };

    const startDrawing = (e: MouseEvent) => {
        if (!isDrawer()) return;
        const pos = getEventPos(e);
        if (!pos) return;
        setIsDrawing(true);
        lastPosRef = pos;
        handleDraw({
            eventType: 'start',
            x: pos.x,
            y: pos.y,
            color: PALETTE[selectedColour()],
            lineWidth: selectedThickness(),
        });
        // Add global event listeners to track mouse outside canvas
        document.addEventListener('mousemove', globalMouseMove);
        document.addEventListener('mouseup', globalMouseUp);
        if (e.cancelable) e.preventDefault();
    };

    const draw = (e: MouseEvent) => {
        // This is now handled by globalMouseMove, but keep for consistency
        globalMouseMove(e);
    };

    const stopDrawing = () => {
        // This is now handled by globalMouseUp, but keep for mouse leave events
        globalMouseUp();
    };

    const clearCanvas = () => {
        if (ctxRef && canvasRef) {
            ctxRef.fillStyle = '#FFFFFF';
            ctxRef.fillRect(0, 0, canvasRef.width, canvasRef.height);
        }
    };

    createEffect(() => {
        actions.setClearCanvas(clearCanvas);
        onCleanup(() => {
            actions.setClearCanvas(null);
            // Clean up any remaining global event listeners
            document.removeEventListener('mousemove', globalMouseMove);
            document.removeEventListener('mouseup', globalMouseUp);
        });
    });

    createEffect(() => {
        if (!canvasRef) return;
        const ctx = canvasRef.getContext('2d');
        ctxRef = ctx;

        canvasRef.width = width;
        canvasRef.height = height;

        if (ctx) {
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
        }

        console.log(
            `[Whiteboard] Initialized with fixed size: ${width}x${height}`
        );
    });

    createEffect(() => {
        // I guess we treat the drawing players canvas as the source of truth
        // makes sense cos they only send draw events never receive them
        if (isDrawer() || !lastDrawEvent() || !ctxRef) return;

        const event = lastDrawEvent();
        if (event?.eventType === 'start') {
            const { x, y } = event;
            remoteLastPosRef = { x, y };
        } else if (event?.eventType === 'end') {
            // No action needed for end event
        } else if (event?.eventType === 'draw') {
            const { x, y, color, lineWidth: lw } = event;
            const eventColor = color || '#000000';
            const eventLineWidth = lw || 3;

            drawLine(
                remoteLastPosRef.x,
                remoteLastPosRef.y,
                x,
                y,
                eventColor,
                eventLineWidth
            );
            remoteLastPosRef = { x, y };
        }
    });

    return (
        <div class="flex flex-row">
            <canvas
                ref={canvasRef}
                class="block rounded-l border-t-2 border-b-2 border-l-2 border-gray-700 bg-white"
                style={{
                    cursor: isDrawer() ? 'crosshair' : 'default',
                    'touch-action': 'none',
                    width: `${width}px`,
                    height: `${height}px`,
                }}
                onMouseDown={startDrawing}
                onMouseMove={draw}
                onMouseUp={stopDrawing}
                onMouseLeave={stopDrawing}
            >
                Your browser does not support the HTML canvas element.
            </canvas>
            <div class="flex flex-col gap-2 rounded-r-lg border-t-2 border-r-2 border-b-2 border-gray-700 bg-gray-100 p-2 align-middle">
                <div
                    class="mx-auto my-2 h-12 w-12 rounded-full border-1 border-gray-700"
                    style={{ 'background-color': PALETTE[selectedColour()] }}
                />
                <div class="grid w-14 grid-cols-2 items-center justify-center">
                    {Object.entries(PALETTE).map(([colour, hex]) => (
                        <div
                            class="h-7 w-7 cursor-pointer border-gray-700 transition-transform duration-150 ease-in-out hover:scale-130"
                            style={{ 'background-color': hex }}
                            onClick={() => setSelectedColour(colour as keyof typeof PALETTE)}
                        />
                    ))}
                </div>
                <div class="mt-4 flex flex-col items-center space-y-2">
                    {[3, 6, 9].map((thickness) => (
                        <div
                            class={classNames(
                                'flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-gray-400 bg-white hover:ring-2 hover:ring-blue-500',
                                {
                                    'ring-2 ring-blue-500 ring-offset-1': selectedThickness() === thickness,
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
            </div>
        </div>
    );
};

export default Whiteboard;
