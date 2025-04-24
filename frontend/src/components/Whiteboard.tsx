import {useRef, useEffect, useState, useCallback} from 'react';

function Whiteboard({isDrawer, onDraw, lastDrawEvent, localPlayerIsDrawer, width, height}: {
    isDrawer: boolean, onDraw: any, lastDrawEvent: any, localPlayerIsDrawer: boolean, width: number, height: number
}) {
    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const ctxRef = useRef<CanvasRenderingContext2D | null>(null); // To store the 2D context
    const [isDrawing, setIsDrawing] = useState(false); // Local drawing state
    const lastPosRef = useRef({x: 0, y: 0}); // Store last position for local drawing

    // Store last remote positions separately
    const remoteLastPosRef = useRef({x: 0, y: 0});
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

        // Handle TouchEvent first
        if (evt.touches && evt.touches.length > 0) {
            clientX = evt.touches[0].clientX;
            clientY = evt.touches[0].clientY;
        } else if (evt.changedTouches && evt.changedTouches.length > 0) { // For touchend/touchcancel
            clientX = evt.changedTouches[0].clientX;
            clientY = evt.changedTouches[0].clientY;
        } else if (evt.clientX !== undefined && evt.clientY !== undefined) { // Handle MouseEvent
            clientX = evt.clientX;
            clientY = evt.clientY;
        } else {
            return null; // Cannot determine coordinates
        }
        // Return coordinates relative to the element's bounding box
        // Adjust coordinates based on the element's actual size vs its buffer size
        const scaleX = canvas.width / rect.width;
        const scaleY = canvas.height / rect.height;
        return {
            x: (clientX - rect.left) * scaleX,
            y: (clientY - rect.top) * scaleY
        };
    }, []); // No dependencies

    const drawLine = useCallback((x1: number, y1: number, x2: number, y2: number, color: string, width: number) => {
        const ctx = ctxRef.current;
        if (!ctx) return;
        // Coordinates are now relative to the canvas buffer size
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = width; // Use provided width (already scaled if needed)
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
        const pos = getEventPos(e); // Gets coords relative to buffer
        if (!pos) return;
        setIsDrawing(true);
        lastPosRef.current = pos; // Store buffer position
        // Send buffer position
        onDraw({eventType: 'start', x: pos.x, y: pos.y, color: strokeColor, lineWidth});
        if (e.cancelable) e.preventDefault();
    }, [isDrawer, getEventPos, onDraw]);

    const draw = useCallback((e: any) => {
        if (!isDrawer || !isDrawing) return;
        const pos = getEventPos(e); // Gets coords relative to buffer
        if (!pos) return;
        drawLine(lastPosRef.current.x, lastPosRef.current.y, pos.x, pos.y, strokeColor, lineWidth); // Draw using buffer coords
        // Send buffer position
        onDraw({eventType: 'draw', x: pos.x, y: pos.y, color: strokeColor, lineWidth});
        lastPosRef.current = pos; // Store buffer position
        if (e.cancelable) e.preventDefault();
    }, [isDrawer, isDrawing, getEventPos, drawLine, onDraw]);

    const stopDrawing = useCallback(() => {
        if (!isDrawer || !isDrawing) return;
        setIsDrawing(false);
        onDraw({eventType: 'end'});
    }, [isDrawer, isDrawing, onDraw]);

    // --- Clear Canvas Function ---
    const clearCanvasLocal = useCallback(() => {
        const ctx = ctxRef.current;
        const canvas = canvasRef.current;
        if (ctx && canvas) {
            ctx.fillStyle = '#FFFFFF';
            ctx.fillRect(0, 0, canvas.width, canvas.height); // Clear based on buffer size
        }
    }, []); // Depends on refs

    // --- Effect for Initial Setup (No Resizing Needed) ---
    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        ctxRef.current = ctx;

        // --- SET FIXED SIZE ---
        canvas.width = width;
        canvas.height = height;
        // --- NO DPR SCALING NEEDED ---
        // canvas.style.width = `${width}px`; // Style set by container now
        // canvas.style.height = `${height}px`;
        // ctx.scale(1, 1); // No scaling

        if (ctx) {
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
            ctx.lineWidth = lineWidth;
            ctx.strokeStyle = strokeColor;
        }

        clearCanvasLocal(); // Initial clear
        console.log(`[Whiteboard] Initialized with fixed size: ${width}x${height}`);

        // No resize listener needed
    }, [width, height, clearCanvasLocal]); // Rerun if fixed dimensions change

    // --- Effect to Clear Canvas on Key Change ---
    useEffect(() => {
        console.log("[Whiteboard] Key changed, clearing canvas.");
        clearCanvasLocal();
    }, [clearCanvasLocal]); // Runs once on mount/key change


    // --- Effect for Handling Remote Draw Events ---
    useEffect(() => {
        // Only process if we are NOT the drawer and event exists
        if (localPlayerIsDrawer || !lastDrawEvent || !ctxRef.current) return;

        const {eventType, x, y, color, lineWidth: lw} = lastDrawEvent;
        const eventColor = color || '#000000';
        const eventLineWidth = lw || 3;
        // --- NO DPR SCALING NEEDED for incoming coords ---
        // Coordinates received from backend should already map to the fixed buffer size

        if (eventType === 'start') {
            setRemoteIsDrawing(true);
            remoteLastPosRef.current = {x, y}; // Store buffer coords
            // drawLine(x, y, x, y, eventColor, eventLineWidth); // Optional dot
        } else if (eventType === 'draw' && remoteIsDrawing) {
            drawLine(remoteLastPosRef.current.x, remoteLastPosRef.current.y, x, y, eventColor, eventLineWidth); // Use buffer coords
            remoteLastPosRef.current = {x, y}; // Store buffer coords
        } else if (eventType === 'end') {
            setRemoteIsDrawing(false);
        }

    }, [lastDrawEvent, localPlayerIsDrawer, remoteIsDrawing, drawLine]); // Dependency on lastDrawEvent


    return (
        <canvas
            ref={canvasRef}
            className="block bg-white" // Removed absolute positioning
            style={{cursor: isDrawer ? 'crosshair' : 'default', touchAction: 'none'}} // Style no longer sets size
            // Width/Height attributes are set in useEffect now
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