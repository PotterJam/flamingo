import { useRef, useEffect, useState, useCallback, FC } from 'react';
import { useAppStore } from '../store';
import { DrawEvent } from '../messages';

const PALETTE: Record<string, string> = {
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
};

interface WhiteboardProps {
    isDrawer: boolean;
    onDraw: (payload: DrawEvent) => void;
    width: number;
    height: number;
}

const Whiteboard: FC<WhiteboardProps> = ({
    isDrawer,
    onDraw,
    width,
    height,
}) => {
    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const ctxRef = useRef<CanvasRenderingContext2D | null>(null);
    const [isDrawing, setIsDrawing] = useState(false);
    const lastPosRef = useRef({ x: 0, y: 0 });

    const lastDrawEvent = useAppStore((s) => s.gameState.lastDrawEvent);
    const setClearCanvas = useAppStore((s) => s.setClearCanvas);

    const remoteLastPosRef = useRef({ x: 0, y: 0 });
    const [remoteIsDrawing, setRemoteIsDrawing] = useState(false);

    const strokeColor = '#000000';
    const lineWidth = 3;

    const getEventPos = (evt: any) => {
        const canvas = canvasRef.current;
        if (!canvas) return null;
        const rect = canvas.getBoundingClientRect();

        const scaleX = canvas.width / rect.width;
        const scaleY = canvas.height / rect.height;
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
        const ctx = ctxRef.current;
        if (!ctx) return;
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = width;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();
        ctx.closePath();
    };

    const startDrawing = useCallback(
        (e: React.MouseEvent<HTMLCanvasElement>) => {
            if (!isDrawer) return;
            const pos = getEventPos(e);
            if (!pos) return;
            setIsDrawing(true);
            lastPosRef.current = pos;
            onDraw({
                eventType: 'start',
                x: pos.x,
                y: pos.y,
                color: strokeColor,
                lineWidth,
            });
            if (e.cancelable) e.preventDefault();
        },
        [isDrawer, getEventPos, onDraw]
    );

    const draw = useCallback(
        (e: React.MouseEvent<HTMLCanvasElement>) => {
            if (!isDrawer || !isDrawing) return;
            const pos = getEventPos(e);
            if (!pos) return;
            drawLine(
                lastPosRef.current.x,
                lastPosRef.current.y,
                pos.x,
                pos.y,
                strokeColor,
                lineWidth
            );
            onDraw({
                eventType: 'draw',
                x: pos.x,
                y: pos.y,
                color: strokeColor,
                lineWidth,
            });
            lastPosRef.current = pos;
            if (e.cancelable) e.preventDefault();
        },
        [isDrawer, isDrawing, getEventPos, drawLine, onDraw]
    );

    const stopDrawing = useCallback(() => {
        if (!isDrawer || !isDrawing) return;
        setIsDrawing(false);
        onDraw({ eventType: 'end' });
    }, [isDrawer, isDrawing, onDraw]);

    // This one does need to be a useCallback
    const clearCanvas = useCallback(() => {
        const ctx = ctxRef.current;
        const canvas = canvasRef.current;
        if (ctx && canvas) {
            ctx.fillStyle = '#FFFFFF';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
    }, []);

    useEffect(() => {
        setClearCanvas(clearCanvas);
        return () => setClearCanvas(null);
    }, [clearCanvas, setClearCanvas]);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        ctxRef.current = ctx;

        canvas.width = width;
        canvas.height = height;

        if (ctx) {
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
            ctx.lineWidth = lineWidth;
            ctx.strokeStyle = strokeColor;
        }

        console.log(
            `[Whiteboard] Initialized with fixed size: ${width}x${height}`
        );
    }, [width, height]);

    useEffect(() => {
        // I guess we treat the drawing players canvas as the source of truth
        // makes sense cos they only send draw events never receive them
        if (isDrawer || !lastDrawEvent || !ctxRef.current) return;

        if (lastDrawEvent.eventType === 'start') {
            const { x, y } = lastDrawEvent;
            setRemoteIsDrawing(true);
            remoteLastPosRef.current = { x, y };
        } else if (lastDrawEvent.eventType === 'end') {
            setRemoteIsDrawing(false);
        } else {
            const { x, y, color, lineWidth: lw } = lastDrawEvent;
            const eventColor = color || '#000000';
            const eventLineWidth = lw || 3;

            drawLine(
                remoteLastPosRef.current.x,
                remoteLastPosRef.current.y,
                x,
                y,
                eventColor,
                eventLineWidth
            );
            remoteLastPosRef.current = { x, y };
        }
    }, [lastDrawEvent, isDrawer, remoteIsDrawing, drawLine]);

    return (
        <div className="flex flex-row">
            <canvas
                ref={canvasRef}
                className="block rounded border-2 border-black bg-white"
                style={{
                    cursor: isDrawer ? 'crosshair' : 'default',
                    touchAction: 'none',
                    width: width,
                    height: height,
                }}
                onMouseDown={startDrawing}
                onMouseMove={draw}
                onMouseUp={stopDrawing}
                onMouseLeave={stopDrawing}
            >
                Your browser does not support the HTML canvas element.
            </canvas>
            <div className="ml-2 flex flex-col gap-2 rounded-lg p-2 align-middle">
                <div className="items-center gap-2 grid gap-x-2 w-16 grid-cols-2 justify-center">
                    {Object.entries(PALETTE).map(([k, v], _) => (
                        <div
                            key={k}
                            className="h-6 w-6 cursor-pointer rounded-full border-gray-700 border-1 hover:ring-2 hover:ring-blue-500"
                            style={{ backgroundColor: v }}
                            // onClick={() => handleColorChange(color)} // TODO: Implement
                        />
                    ))}
                </div>
                <div className="flex flex-col space-y-1">
                    {[2, 5, 10].map((thickness) => (
                        <button
                            key={thickness}
                            className="rounded border border-gray-300 p-1 text-xs hover:bg-gray-200 focus:ring-2 focus:ring-blue-500 focus:outline-none"
                            // onClick={() => handleThicknessChange(thickness)} // TODO: Implement
                        >
                            {thickness}px
                        </button>
                    ))}
                </div>
            </div>
        </div>
    );
};

export default Whiteboard;
