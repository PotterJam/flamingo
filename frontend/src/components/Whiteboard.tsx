import { useRef, useEffect, useState, useCallback, FC } from 'react';
import { useAppStore } from '../store';
import { DrawEvent } from '../messages';

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

        clearCanvas();
        console.log(
            `[Whiteboard] Initialized with fixed size: ${width}x${height}`
        );
    }, [width, height, clearCanvas]);

    useEffect(() => {
        console.log('[Whiteboard] Key changed, clearing canvas.');
        clearCanvas();
    }, [clearCanvas]);

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
        <canvas
            ref={canvasRef}
            className="block bg-white"
            style={{
                cursor: isDrawer ? 'crosshair' : 'default',
                touchAction: 'none',
            }}
            onMouseDown={startDrawing}
            onMouseMove={draw}
            onMouseUp={stopDrawing}
            onMouseLeave={stopDrawing}
        >
            Your browser does not support the HTML canvas element.
        </canvas>
    );
};

export default Whiteboard;
