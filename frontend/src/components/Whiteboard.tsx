import { useRef, useEffect, useState, useCallback } from 'react';

function Whiteboard({ isDrawer, onDraw, lastDrawEvent, localPlayerIsDrawer }: { isDrawer: boolean, onDraw: any, lastDrawEvent: any, localPlayerIsDrawer: boolean }) {
    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const ctxRef = useRef<CanvasRenderingContext2D | null>(null); // To store the 2D context
    const [isDrawing, setIsDrawing] = useState(false); // Local drawing state
    const lastPosRef = useRef({ x: 0, y: 0 }); // Store last position for local drawing

    // Store last remote positions separately
    const remoteLastPosRef = useRef({ x: 0, y: 0 });
    const [remoteIsDrawing, setRemoteIsDrawing] = useState(false);

    // Drawing config (could be props later)
    const strokeColor = '#000000';
    const lineWidth = 3;

    // --- Utility Functions ---
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
        } else if (evt.clientX !== undefined) {
            clientX = evt.clientX;
            clientY = evt.clientY;
        } else {
            return null;
        }
        return { x: clientX - rect.left, y: clientY - rect.top };
    }, []); // No dependencies

    const drawLine = useCallback((x1: number, y1: number, x2: number, y2: number, color: string, width: number) => {
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
    }, []); // No dependencies

    // --- Event Handlers for Local Drawing ---
    const startDrawing = useCallback((e: any) => {
        if (!isDrawer) return;
        const pos = getEventPos(e);
        if (!pos) return;
        setIsDrawing(true);
        lastPosRef.current = pos;
        onDraw({ eventType: 'start', ...pos, color: strokeColor, lineWidth });
        if (e.cancelable) e.preventDefault();
    }, [isDrawer, getEventPos, onDraw]);

    const draw = useCallback((e: any) => {
        if (!isDrawer || !isDrawing) return;
        const pos = getEventPos(e);
        if (!pos) return;
        drawLine(lastPosRef.current.x, lastPosRef.current.y, pos.x, pos.y, strokeColor, lineWidth);
        onDraw({ eventType: 'draw', ...pos, color: strokeColor, lineWidth });
        lastPosRef.current = pos;
        if (e.cancelable) e.preventDefault();
    }, [isDrawer, isDrawing, getEventPos, drawLine, onDraw]);

    const stopDrawing = useCallback(() => {
        if (!isDrawer || !isDrawing) return;
        setIsDrawing(false);
        onDraw({ eventType: 'end' });
    }, [isDrawer, isDrawing, onDraw]);

    // --- Effect for Initial Setup & Resizing ---
    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        ctxRef.current = ctx;

        const resizeCanvas = () => {
            const parent = canvas.parentElement;
            if (!parent) return;
            const { width } = parent.getBoundingClientRect();
            if (width <= 0) return;
            const height = (width * 9) / 16; // Maintain aspect ratio

            if (!ctx) return;

            // Simple clear on resize for React - preserving drawing is more complex
            // Store state outside if needed, or redraw based on event history
            canvas.width = width;
            canvas.height = height;
            ctx.fillStyle = '#FFFFFF';
            ctx?.fillRect(0, 0, width, height);
        };

        resizeCanvas(); // Initial size
        window.addEventListener('resize', resizeCanvas);

        // Cleanup
        return () => {
            window.removeEventListener('resize', resizeCanvas);
        };
    }, []); // Run only once on mount

    // --- Effect for Handling Remote Draw Events ---
    useEffect(() => {
        // Only process if we are NOT the drawer and event exists
        if (localPlayerIsDrawer || !lastDrawEvent) return;

        const { eventType, x, y, color, lineWidth: lw } = lastDrawEvent;
        const eventColor = color || '#000000';
        const eventLineWidth = lw || 3;

        if (eventType === 'start') {
            setRemoteIsDrawing(true);
            remoteLastPosRef.current = { x, y };
            // Optional: draw dot
            // drawLine(x, y, x, y, eventColor, eventLineWidth);
        } else if (eventType === 'draw' && remoteIsDrawing) {
            drawLine(remoteLastPosRef.current.x, remoteLastPosRef.current.y, x, y, eventColor, eventLineWidth);
            remoteLastPosRef.current = { x, y };
        } else if (eventType === 'end') {
            setRemoteIsDrawing(false);
        }

    }, [lastDrawEvent, localPlayerIsDrawer, remoteIsDrawing, drawLine]); // Dependency on lastDrawEvent

    // Public method simulation (less common in React, use props/state)
    // const clearCanvas = useCallback(() => {
    // 	const ctx = ctxRef.current;
    // 	const canvas = canvasRef.current;
    // 	if (ctx && canvas) {
    // 		ctx.fillStyle = '#FFFFFF';
    // 		ctx.fillRect(0, 0, canvas.width, canvas.height);
    // 	}
    // }, []);
    // Expose via ref if needed, but key prop reset is preferred

    return (
        <canvas
            ref={canvasRef}
            className="w-full h-full block bg-white"
            style={{ cursor: isDrawer ? 'crosshair' : 'default', touchAction: 'none' }}
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
