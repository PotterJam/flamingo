import { CANVAS_WIDTH, CANVAS_HEIGHT, clear, drawBetween, fill } from "../lib/canvas";

export type DrawEvent =
  | { event_type: "start"; x: number; y: number; color: string; line_width: number }
  | { event_type: "draw"; start_x: number; start_y: number; end_x: number; end_y: number; color: string; line_width: number }
  | { event_type: "end"; start_x: number; start_y: number; end_x: number; end_y: number; color: string; line_width: number }
  | { event_type: "fill"; x: number; y: number; color: string }
  | { event_type: "clear" }
  | { event_type: "undo" }
  | { event_type: "redo" };

interface Point {
  x: number;
  y: number;
}

type ActiveTool = "pen" | "fill";

interface DrawingCanvasHook {
  el: HTMLElement;
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  isDrawer: boolean;
  isPainting: boolean;
  lastCoord: Point | null;
  selectedColor: string;
  selectedThickness: number;
  activeTool: ActiveTool;
  eventStack: DrawEvent[];
  redoStack: DrawEvent[][];
  finalReplayToken: number;
  replayFinalDrawingListener?: () => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
  pushEvent: (event: string, payload: DrawEvent) => void;
  replayFinalDrawing: () => void;
  setupDrawerEvents: () => void;
  setupToolbar: () => void;
  performUndo: () => void;
  performRedo: () => void;
  performClear: () => void;
}

const isUndoBoundary = (type: string) =>
  type === "start" || type === "fill" || type === "clear";

const canvasEffect = (
  ctx: CanvasRenderingContext2D,
  fn: (imageData: ImageData) => void
) => {
  const imageData = ctx.getImageData(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
  fn(imageData);
  ctx.putImageData(imageData, 0, 0);
};

const renderDrawEvent = (imageData: ImageData, event: DrawEvent) => {
  switch (event.event_type) {
    case "start":
      drawBetween(event.x, event.y, event.x, event.y, event.line_width, event.color, imageData);
      break;
    case "draw":
    case "end":
      drawBetween(event.start_x, event.start_y, event.end_x, event.end_y, event.line_width, event.color, imageData);
      break;
    case "fill":
      fill(event.x, event.y, event.color, imageData);
      break;
    case "clear":
      clear(imageData);
      break;
  }
};

const renderEvents = (ctx: CanvasRenderingContext2D, events: DrawEvent[]) => {
  canvasEffect(ctx, (imageData) => {
    clear(imageData);
    for (const e of events) {
      renderDrawEvent(imageData, e);
    }
  });
};

export const replayEvents = (
  ctx: CanvasRenderingContext2D,
  events: DrawEvent[],
  isCurrentReplay: () => boolean,
  delayMs = 15
) => {
  canvasEffect(ctx, (imageData) => clear(imageData));

  if (events.length === 0) return;

  let index = 0;

  const renderNext = () => {
    if (!isCurrentReplay()) return;

    canvasEffect(ctx, (imageData) => {
      renderDrawEvent(imageData, events[index]);
    });

    index += 1;

    if (index < events.length) {
      window.setTimeout(renderNext, delayMs);
    }
  };

  window.setTimeout(renderNext, delayMs);
};

const findUndoBoundaryIndex = (events: DrawEvent[]): number => {
  for (let i = events.length - 1; i >= 0; i--) {
    if (isUndoBoundary(events[i].event_type)) {
      return i;
    }
  }
  return -1;
};

const translatePointerToCanvas = (e: PointerEvent, canvas: HTMLCanvasElement): [number, number] => {
  const rect = canvas.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
};

const DrawingCanvas = {
  mounted(this: DrawingCanvasHook) {
    this.canvas = this.el.querySelector("canvas") as HTMLCanvasElement;
    this.ctx = this.canvas.getContext("2d", { willReadFrequently: true })!;
    this.isDrawer = this.el.dataset.isDrawer === "true";
    this.isPainting = false;
    this.lastCoord = null as Point | null;
    this.selectedColor = "#000000";
    this.selectedThickness = 9;
    this.activeTool = "pen";
    this.eventStack = [] as DrawEvent[];
    this.redoStack = [] as DrawEvent[][];
    this.finalReplayToken = 0;

    canvasEffect(this.ctx, (imageData: ImageData) => clear(imageData));

    if (this.el.dataset.finalDrawingEvents) {
      const events = JSON.parse(this.el.dataset.finalDrawingEvents) as DrawEvent[];
      this.eventStack = [...events];
      this.replayFinalDrawing();
    }

    if (this.isDrawer) {
      this.setupDrawerEvents();
      this.setupToolbar();
    }

    this.handleEvent("draw_event", (event: DrawEvent) => {
      if (this.isDrawer) return;

      if (event.event_type === "undo") {
        const idx = findUndoBoundaryIndex(this.eventStack);
        if (idx >= 0) {
          this.eventStack.splice(idx);
        }
        renderEvents(this.ctx, this.eventStack);
        return;
      }

      this.eventStack.push(event);
      canvasEffect(this.ctx, (imageData: ImageData) => {
        renderDrawEvent(imageData, event);
      });
    });

    this.handleEvent("drawing_state", (data: { events: DrawEvent[] }) => {
      this.eventStack = [...data.events];
      renderEvents(this.ctx, data.events);
    });

    this.replayFinalDrawingListener = () => {
      this.replayFinalDrawing();
    };
    window.addEventListener("flamingo:replay-final-drawings", this.replayFinalDrawingListener);
  },

  replayFinalDrawing(this: DrawingCanvasHook) {
    if (this.el.dataset.finalDrawingReplay !== "true") return;

    this.finalReplayToken += 1;
    const token = this.finalReplayToken;

    replayEvents(
      this.ctx,
      this.eventStack,
      () => this.finalReplayToken === token
    );
  },

  setupDrawerEvents(this: DrawingCanvasHook) {
    const canvas = this.canvas as HTMLCanvasElement;

    const pushDrawEvent = (event: DrawEvent) => {
      this.eventStack.push(event);
      this.redoStack = [];
      canvasEffect(this.ctx, (imageData: ImageData) => renderDrawEvent(imageData, event));
      this.pushEvent("draw_event", event);
    };

    canvas.addEventListener("pointerdown", (e: PointerEvent) => {
      e.preventDefault();
      const [x, y] = translatePointerToCanvas(e, canvas);

      if (this.activeTool === "fill") {
        const fillEvent: DrawEvent = {
          event_type: "fill", x: Math.round(x), y: Math.round(y), color: this.selectedColor,
        };
        pushDrawEvent(fillEvent);
        return;
      }

      this.isPainting = true;
      this.lastCoord = { x, y };

      const startEvent: DrawEvent = {
        event_type: "start", x, y,
        color: this.selectedColor, line_width: this.selectedThickness,
      };
      pushDrawEvent(startEvent);
    });

    canvas.addEventListener("pointermove", (e: PointerEvent) => {
      if (!this.isPainting) return;
      e.preventDefault();

      const [x, y] = translatePointerToCanvas(e, canvas);
      const prev: Point = this.lastCoord ?? { x, y };
      this.lastCoord = { x, y };

      const drawEvent: DrawEvent = {
        event_type: "draw",
        start_x: prev.x, start_y: prev.y, end_x: x, end_y: y,
        color: this.selectedColor, line_width: this.selectedThickness,
      };
      pushDrawEvent(drawEvent);
    });

    const handlePointerUp = (e: PointerEvent) => {
      if (!this.isPainting) return;
      this.isPainting = false;

      const [x, y] = translatePointerToCanvas(e, canvas);
      const prev: Point = this.lastCoord ?? { x, y };
      this.lastCoord = null;

      const endEvent: DrawEvent = {
        event_type: "end",
        start_x: prev.x, start_y: prev.y, end_x: x, end_y: y,
        color: this.selectedColor, line_width: this.selectedThickness,
      };
      pushDrawEvent(endEvent);
    };

    canvas.addEventListener("pointerup", handlePointerUp);
    canvas.addEventListener("pointerleave", handlePointerUp);

    canvas.addEventListener("pointerenter", (e: PointerEvent) => {
      if (e.buttons === 1 && this.activeTool === "pen") {
        const [x, y] = translatePointerToCanvas(e, canvas);
        this.isPainting = true;
        this.lastCoord = { x, y };
        const startEvent: DrawEvent = {
          event_type: "start", x, y,
          color: this.selectedColor, line_width: this.selectedThickness,
        };
        pushDrawEvent(startEvent);
      }
    });
  },

  performUndo(this: DrawingCanvasHook) {
    const idx = findUndoBoundaryIndex(this.eventStack);
    if (idx < 0) return;

    const removed = this.eventStack.splice(idx);
    this.redoStack.push(removed);
    renderEvents(this.ctx, this.eventStack);
    this.pushEvent("draw_event", { event_type: "undo" });
  },

  performRedo(this: DrawingCanvasHook) {
    if (this.redoStack.length === 0) return;

    const restored = this.redoStack.pop()!;
    for (const event of restored) {
      this.eventStack.push(event);
      this.pushEvent("draw_event", event);
    }
    renderEvents(this.ctx, this.eventStack);
  },

  performClear(this: DrawingCanvasHook) {
    const clearEvent: DrawEvent = { event_type: "clear" };
    this.eventStack.push(clearEvent);
    this.redoStack = [];
    canvasEffect(this.ctx, (imageData: ImageData) => clear(imageData));
    this.pushEvent("draw_event", clearEvent);
  },

  setupToolbar(this: DrawingCanvasHook) {
    const selectGroup = (attr: string, ringClasses: string[], onSelect: (value: string) => void) => {
      this.el.querySelectorAll(`[${attr}]`).forEach((btn: HTMLElement) => {
        btn.addEventListener("click", () => {
          onSelect(btn.dataset[attr.replace("data-", "")]!);
          this.el.querySelectorAll(`[${attr}]`).forEach((b: HTMLElement) => {
            b.classList.remove(...ringClasses);
          });
          btn.classList.add(...ringClasses);
        });
      });
    };

    selectGroup("data-color", ["ring-2", "ring-offset-1"], (v) => { this.selectedColor = v; });
    selectGroup("data-size", ["bg-pink-300"], (v) => { this.selectedThickness = parseInt(v, 10); });
    selectGroup("data-tool", ["bg-pink-300"], (v) => { this.activeTool = v; });

    this.el.querySelector("[data-action='undo']")?.addEventListener("click", () => {
      this.performUndo();
    });

    this.el.querySelector("[data-action='redo']")?.addEventListener("click", () => {
      this.performRedo();
    });

    this.el.querySelector("[data-action='clear']")?.addEventListener("click", () => {
      this.performClear();
    });

    this.el.querySelector(`[data-color="#000000"]`)?.classList.add("ring-2", "ring-offset-1");
    this.el.querySelector(`[data-size="9"]`)?.classList.add("bg-pink-300");
    this.el.querySelector(`[data-tool="pen"]`)?.classList.add("bg-pink-300");
  },

  destroyed(this: DrawingCanvasHook) {
    this.finalReplayToken += 1;

    if (this.replayFinalDrawingListener) {
      window.removeEventListener("flamingo:replay-final-drawings", this.replayFinalDrawingListener);
    }
  },
};

export default DrawingCanvas;
