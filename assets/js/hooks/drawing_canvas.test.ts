import { expect, test } from "bun:test";
import DrawingCanvas, { fadingEvent, opsToEvents, type DrawEvent } from "./drawing_canvas";

test.each(["single_stroke", ""] as const)("pointer release and cancellation with constraint %s", (constraint) => {
  const listeners = new Map<string, (event: PointerEvent) => void>();
  const sent: DrawEvent[] = [];
  const imageData = { data: new Uint8ClampedArray(700 * 500 * 4) };
  const hook = {
    constraint,
    canvas: {
      clientWidth: 700, clientHeight: 500,
      addEventListener: (name: string, listener: (event: PointerEvent) => void) => listeners.set(name, listener),
      setPointerCapture: () => {},
    },
    ctx: { getImageData: () => imageData, putImageData: () => {} },
    isPainting: false, strokeUsed: false, lastCoord: null, straightStart: null,
    activeTool: "pen", selectedColor: "#000000", selectedThickness: 9,
    eventStack: [], redoStack: [],
    pushEvent: (_name: string, event: DrawEvent) => sent.push(event),
  };
  DrawingCanvas.setupDrawerEvents.call(hook as unknown as ThisParameterType<typeof DrawingCanvas.setupDrawerEvents>);
  const pointer = (type: string, x: number, y: number) => listeners.get(type)!({
    offsetX: x, offsetY: y, pointerId: 1, preventDefault() {},
  } as PointerEvent);

  pointer("pointermove", 10, 15);
  expect(sent).toHaveLength(0);
  pointer("pointerdown", 20, 30);
  pointer("pointermove", 50, 70);
  pointer("pointerup", 50, 70);
  pointer("pointermove", 80, 90);
  pointer("pointerdown", 110, 130);
  pointer("pointermove", 140, 160);
  pointer("pointercancel", 140, 160);
  pointer("pointermove", 170, 190);

  if (constraint === "single_stroke") {
    expect(sent.map((event) => event.event_type)).toEqual(["start", "draw", "draw", "draw", "draw"]);
    expect(sent.slice(2)).toEqual([
      { event_type: "draw", start_x: 50, start_y: 70, end_x: 80, end_y: 90, color: "#000000", line_width: 9 },
      { event_type: "draw", start_x: 80, start_y: 90, end_x: 140, end_y: 160, color: "#000000", line_width: 9 },
      { event_type: "draw", start_x: 140, start_y: 160, end_x: 170, end_y: 190, color: "#000000", line_width: 9 },
    ]);
    expect(hook.isPainting).toBe(true);
  } else {
    expect(sent.map((event) => event.event_type)).toEqual(["start", "draw", "end", "start", "draw", "end"]);
    expect(hook.isPainting).toBe(false);
  }
});

test("ink fades by age, expires at five seconds, and leaves the archive untouched", () => {
  const event: DrawEvent = {
    event_type: "start", x: 37, y: 81, color: "#204080", line_width: 9, drawn_at: 1000,
  };
  expect(fadingEvent(event, 500)).toEqual(event);
  expect(fadingEvent(event, 3500)).toEqual({ ...event, color: "#90a0c0" });
  expect(fadingEvent(event, 5999)).not.toBeNull();
  expect(fadingEvent(event, 6000)).toBeNull();
  expect(event.color).toBe("#204080");
  expect(fadingEvent({ event_type: "clear", drawn_at: 1000 }, 9000)).toEqual({ event_type: "clear", drawn_at: 1000 });
});

test("final replay retains rainbow colours and big brush widths without fading", () => {
  const events = opsToEvents([["p", "#2563eb", 45, [30, 70, 10, 20]], ["p", "#db2777", 9, [90, 20]]]);
  expect(events).toEqual([
    { event_type: "start", x: 30, y: 70, color: "#2563eb", line_width: 45 },
    { event_type: "draw", start_x: 30, start_y: 70, end_x: 40, end_y: 90, color: "#2563eb", line_width: 45 },
    { event_type: "start", x: 90, y: 20, color: "#db2777", line_width: 9 },
  ]);
  expect(fadingEvent(events[0], 999999)).toEqual(events[0]);
});
