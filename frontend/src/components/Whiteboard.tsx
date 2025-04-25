import { useRef, useEffect, useState, useCallback } from 'react';
import { useAppStore } from '../store';

function Whiteboard({
    isDrawer,
    onDraw,
    localPlayerIsDrawer,
    width,
    height,
}: {
    isDrawer: boolean;
    onDraw: any;
    localPlayerIsDrawer: boolean;
    width: number;
    height: number;
}) {
    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const ctxRef = useRef<CanvasRenderingContext2D | null>(null);
    const [isDrawing, setIsDrawing] = useState(false);
    const lastPosRef = useRef({ x: 0, y: 0 });

    const lastDrawEvent = useAppStore((s) => s.gameState.lastDrawEvent);

    const remoteLastPosRef = useRef({ x: 0, y: 0 });
    const [remoteIsDrawing, setRemoteIsDrawing] = useState(false);

    const strokeColor = '#000000';
    const lineWidth = 3;

    const getEventPos = useCallback((evt: any) => {
        const canvas = canvasRef.current;
        if (!canvas) return null;
        const rect = canvas.getBoundingClientRect();
        let clientX, clientY;

        if (evt.touches && evt.touches.length > 0) {
            clientX = evt.touches[0].clientX;
            clientY = evt.touches[0].clientY;
        } else if (evt.changedTouches && evt.changedTouches.length > 0) {
            clientX = evt.changedTouches[0].clientX;
            clientY = evt.changedTouches[0].clientY;
        } else if (evt.clientX !== undefined && evt.clientY !== undefined) {
            clientX = evt.clientX;
            clientY = evt.clientY;
        } else {
            return null;
        }

        const scaleX = canvas.width / rect.width;
        const scaleY = canvas.height / rect.height;
        return {
            x: (clientX - rect.left) * scaleX,
            y: (clientY - rect.top) * scaleY,
        };
    }, []);

    const drawLine = useCallback(
        (
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
        },
        []
    );

    const startDrawing = useCallback(
        (e: any) => {
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
        (e: any) => {
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

    const clearCanvasLocal = useCallback(() => {
        const ctx = ctxRef.current;
        const canvas = canvasRef.current;
        if (ctx && canvas) {
            ctx.fillStyle = '#FFFFFF';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
    }, []);

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

        clearCanvasLocal();
        console.log(
            `[Whiteboard] Initialized with fixed size: ${width}x${height}`
        );
    }, [width, height, clearCanvasLocal]);

    useEffect(() => {
        console.log('[Whiteboard] Key changed, clearing canvas.');
        clearCanvasLocal();
    }, [clearCanvasLocal]);

    useEffect(() => {
        // I guess we treat the drawing players canvas as the source of truth
        // makes sense cos they only send draw events never receive them
        if (localPlayerIsDrawer || !lastDrawEvent || !ctxRef.current) return;

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
    }, [lastDrawEvent, localPlayerIsDrawer, remoteIsDrawing, drawLine]);

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
            onTouchStart={startDrawing}
            onTouchMove={draw}
            onTouchEnd={stopDrawing}
            onTouchCancel={stopDrawing}
        >
            Your browser does not support the HTML canvas element.
        </canvas>
    );
}

export default Whiteboard;
