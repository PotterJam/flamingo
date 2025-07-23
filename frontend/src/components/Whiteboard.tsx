import { createSignal, createEffect, onCleanup, Component } from 'solid-js';
import { actions, store } from '../store';
import { DrawEvent } from '../messages';
import classNames from 'classnames';
import { Separator } from './ui/separator';
import { getStroke } from 'perfect-freehand';
import {FaSolidArrowRotateLeft} from "solid-icons/fa";

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

const defaultBrushThickness = 9;

const Whiteboard: Component<WhiteboardProps> = ({ height, width }) => {
    let canvasRef: HTMLCanvasElement | undefined;
    let ctxRef: CanvasRenderingContext2D | null = null;
    const [isDrawing, setIsDrawing] = createSignal(false);
    let currentStroke: Array<[number, number, number]> = []; // [x, y, pressure]

    const [selectedColour, setSelectedColour] =
        createSignal<keyof typeof PALETTE>('black');
    const [selectedThickness, setSelectedThickness] = createSignal(defaultBrushThickness);

    const lastDrawEvent = () => store.gameState.lastDrawEvent;
    const isDrawer = () =>
        store.gameState.localPlayerId === store.gameState.currentDrawerId;

    let remoteCurrentStroke: Array<[number, number, number]> = [];
    let remoteStrokeColor = '#000000';
    let remoteStrokeSize = 3;

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

    const drawStroke = (points: Array<[number, number, number]>, color: string, size: number, clear = false) => {
        if (!ctxRef || points.length === 0) return;
        
        // Clear canvas if this is a fresh stroke (for real-time drawing)
        if (clear && canvasRef) {
            ctxRef.fillStyle = '#FFFFFF';
            ctxRef.fillRect(0, 0, canvasRef.width, canvasRef.height);
        }
        
        const stroke = getStroke(points, {
            size,
            thinning: 0.5,
            smoothing: 0.3,
            streamline: 0.6,
            start: {
                taper: false,
            },
            end: {
                taper: false,
            }
        });

        if (stroke.length === 0) return;

        ctxRef.fillStyle = color;
        ctxRef.beginPath();
        ctxRef.moveTo(stroke[0][0], stroke[0][1]);

        for (let i = 1; i < stroke.length; i++) {
            ctxRef.lineTo(stroke[i][0], stroke[i][1]);
        }

        ctxRef.closePath();
        ctxRef.fill();
    };

    // Store completed strokes to redraw when needed
    let completedStrokes: Array<{
        points: Array<[number, number, number]>;
        color: string;
        size: number;
    }> = [];

    const redrawCanvas = () => {
        if (!ctxRef || !canvasRef) return;
        
        // Clear canvas
        ctxRef.fillStyle = '#FFFFFF';
        ctxRef.fillRect(0, 0, canvasRef.width, canvasRef.height);
        
        // Redraw all completed strokes
        completedStrokes.forEach(stroke => {
            drawStroke(stroke.points, stroke.color, stroke.size);
        });
        
        // Draw current stroke if drawing
        if (currentStroke.length > 0) {
            drawStroke(currentStroke, PALETTE[selectedColour()], selectedThickness());
        }
        
        // Draw remote stroke if in progress
        if (remoteCurrentStroke.length > 0) {
            drawStroke(remoteCurrentStroke, remoteStrokeColor, remoteStrokeSize);
        }
    };

    const globalMouseMove = (e: MouseEvent) => {
        if (!isDrawer() || !isDrawing()) return;
        const pos = getEventPos(e);
        if (!pos) return;
        
        // Add point to current stroke with simulated pressure
        const pressure = 0.5; // Could be enhanced with actual pressure data
        currentStroke.push([pos.x, pos.y, pressure]);
        
        // Redraw entire canvas with current stroke
        redrawCanvas();
        
        handleDraw({
            eventType: 'draw',
            x: pos.x,
            y: pos.y,
            color: PALETTE[selectedColour()],
            lineWidth: selectedThickness(),
        });
        
        if (e.cancelable) e.preventDefault();
    };

    const globalMouseUp = () => {
        if (!isDrawer() || !isDrawing()) return;
        setIsDrawing(false);
        
        // Finalize the stroke
        if (currentStroke.length > 0) {
            completedStrokes.push({
                points: [...currentStroke],
                color: PALETTE[selectedColour()],
                size: selectedThickness()
            });
            currentStroke = [];
            redrawCanvas();
        }
        
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
        
        // Start new stroke
        const pressure = 0.5;
        currentStroke = [[pos.x, pos.y, pressure]];
        
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
            completedStrokes = [];
            currentStroke = [];
            remoteCurrentStroke = [];
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

    // Clean up drawing state when player is no longer the drawer
    createEffect(() => {
        if (!isDrawer() && isDrawing()) {
            // Player is no longer the drawer but still has active drawing state
            setIsDrawing(false);
            // Remove global event listeners
            document.removeEventListener('mousemove', globalMouseMove);
            document.removeEventListener('mouseup', globalMouseUp);
        }
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
            const { x, y, color, lineWidth } = event;
            const pressure = 0.5;
            remoteCurrentStroke = [[x, y, pressure]];
            remoteStrokeColor = color || '#000000';
            remoteStrokeSize = lineWidth || 3;
        } else if (event?.eventType === 'end') {
            // Finalize the remote stroke
            if (remoteCurrentStroke.length > 0) {
                completedStrokes.push({
                    points: [...remoteCurrentStroke],
                    color: remoteStrokeColor,
                    size: remoteStrokeSize
                });
                remoteCurrentStroke = [];
                redrawCanvas();
            }
        } else if (event?.eventType === 'draw') {
            const { x, y } = event;
            const pressure = 0.5;

            // Add point to remote stroke
            remoteCurrentStroke.push([x, y, pressure]);
            
            // Redraw entire canvas with remote stroke in progress
            redrawCanvas();
        }
    });

    return (
        <div class="flex flex-col">
            <canvas
                ref={canvasRef}
                class="block bg-white"
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
                    <button onClick={() => store.sendMessage({ type: "drawPathUndo", payload: {}})}>
                        <FaSolidArrowRotateLeft></FaSolidArrowRotateLeft>
                    </button>
                </div>
            </div>
        </div>
    );
};

export default Whiteboard;
