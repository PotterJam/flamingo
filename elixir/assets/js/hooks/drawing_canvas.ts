import { CANVAS_WIDTH, CANVAS_HEIGHT, clear, drawBetween } from "../lib/canvas";

type DrawEvent =
  | { event_type: "start"; x: number; y: number; color: string; line_width: number }
  | { event_type: "draw"; start_x: number; start_y: number; end_x: number; end_y: number; color: string; line_width: number }
  | { event_type: "end"; start_x: number; start_y: number; end_x: number; end_y: number; color: string; line_width: number };

interface Point {
  x: number;
  y: number;
}

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
  }
};

const replayEvents = (ctx: CanvasRenderingContext2D, events: DrawEvent[]) => {
  canvasEffect(ctx, (imageData) => {
    clear(imageData);
    for (const e of events) {
      renderDrawEvent(imageData, e);
    }
  });
};

const translatePointerToCanvas = (e: PointerEvent, canvas: HTMLCanvasElement): [number, number] => {
  const rect = canvas.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
};

const DrawingCanvas = {
  mounted(this: any) {
    this.canvas = this.el.querySelector("canvas") as HTMLCanvasElement;
    this.ctx = this.canvas.getContext("2d", { willReadFrequently: true })!;
    this.isDrawer = this.el.dataset.isDrawer === "true";
    this.isPainting = false;
    this.lastCoord = null as Point | null;
    this.selectedColor = "#000000";
    this.selectedThickness = 9;

    canvasEffect(this.ctx, (imageData: ImageData) => clear(imageData));

    if (this.isDrawer) {
      this.setupDrawerEvents();
      this.setupToolbar();
    }

    this.handleEvent("draw_event", (event: DrawEvent) => {
      if (this.isDrawer) return;

      canvasEffect(this.ctx, (imageData: ImageData) => {
        renderDrawEvent(imageData, event);
      });
    });

    this.handleEvent("drawing_state", (data: { events: DrawEvent[] }) => {
      replayEvents(this.ctx, data.events);
    });
  },

  setupDrawerEvents(this: any) {
    const canvas = this.canvas as HTMLCanvasElement;

    canvas.addEventListener("pointerdown", (e: PointerEvent) => {
      e.preventDefault();
      this.isPainting = true;
      const [x, y] = translatePointerToCanvas(e, canvas);
      this.lastCoord = { x, y };

      const startEvent: DrawEvent = {
        event_type: "start", x, y,
        color: this.selectedColor, line_width: this.selectedThickness,
      };
      canvasEffect(this.ctx, (imageData: ImageData) => renderDrawEvent(imageData, startEvent));
      this.pushEvent("draw_event", startEvent);
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
      canvasEffect(this.ctx, (imageData: ImageData) => renderDrawEvent(imageData, drawEvent));
      this.pushEvent("draw_event", drawEvent);
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
      canvasEffect(this.ctx, (imageData: ImageData) => renderDrawEvent(imageData, endEvent));
      this.pushEvent("draw_event", endEvent);
    };

    canvas.addEventListener("pointerup", handlePointerUp);
    canvas.addEventListener("pointerleave", handlePointerUp);

    canvas.addEventListener("pointerenter", (e: PointerEvent) => {
      if (e.buttons === 1) {
        const [x, y] = translatePointerToCanvas(e, canvas);
        this.isPainting = true;
        this.lastCoord = { x, y };
        const startEvent: DrawEvent = {
          event_type: "start", x, y,
          color: this.selectedColor, line_width: this.selectedThickness,
        };
        canvasEffect(this.ctx, (imageData: ImageData) => renderDrawEvent(imageData, startEvent));
        this.pushEvent("draw_event", startEvent);
      }
    });
  },

  setupToolbar(this: any) {
    this.el.querySelectorAll("[data-color]").forEach((btn: HTMLElement) => {
      btn.addEventListener("click", () => {
        this.selectedColor = btn.dataset.color;
        this.el.querySelectorAll("[data-color]").forEach((b: HTMLElement) => {
          b.classList.remove("ring-2", "ring-offset-1");
        });
        btn.classList.add("ring-2", "ring-offset-1");
      });
    });

    this.el.querySelectorAll("[data-size]").forEach((btn: HTMLElement) => {
      btn.addEventListener("click", () => {
        this.selectedThickness = parseInt(btn.dataset.size!, 10);
        this.el.querySelectorAll("[data-size]").forEach((b: HTMLElement) => {
          b.classList.remove("ring-2");
        });
        btn.classList.add("ring-2");
      });
    });

    this.el.querySelector(`[data-color="#000000"]`)?.classList.add("ring-2", "ring-offset-1");
    this.el.querySelector(`[data-size="9"]`)?.classList.add("ring-2");
  },
};

export default DrawingCanvas;
