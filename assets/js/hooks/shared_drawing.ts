import { DrawEvent, replayEvents } from "./drawing_canvas";

type SharedDrawingPayload = {
  drawer_name: string;
  word: string;
  round_number: number;
  events: DrawEvent[];
};

interface SharedDrawingHook {
  el: HTMLElement;
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  events: DrawEvent[];
  replayToken: number;
  loadDrawing: () => void;
  replay: () => void;
  showInvalid: () => void;
  showDrawing: (drawing: SharedDrawingPayload) => void;
}

const decodeBase64Url = (encoded: string) => {
  const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
  const binary = window.atob(padded);

  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
};

const decodeBase64UrlJson = (encoded: string) =>
  JSON.parse<SharedDrawingPayload>(
    new TextDecoder().decode(decodeBase64Url(encoded))
  );

const SharedDrawing = {
  mounted(this: SharedDrawingHook) {
    this.canvas = this.el.querySelector("canvas") as HTMLCanvasElement;
    this.ctx = this.canvas.getContext("2d", { willReadFrequently: true })!;
    this.events = [];
    this.replayToken = 0;

    this.el.querySelector("[data-replay-shared-drawing]")?.addEventListener("click", () => {
      this.replay();
    });

    this.loadDrawing();
  },

  loadDrawing(this: SharedDrawingHook) {
    const encoded = window.location.hash.slice(1);

    if (encoded) {
      try {
        this.showDrawing(decodeBase64UrlJson(encoded));
      } catch {
        this.showInvalid();
      }
    } else {
      this.showInvalid();
    }
  },

  replay(this: SharedDrawingHook) {
    this.replayToken += 1;
    const token = this.replayToken;

    replayEvents(this.ctx, this.events, () => this.replayToken === token);
  },

  showInvalid() {
    window.location.replace("/drawing/invalid");
  },

  showDrawing(this: SharedDrawingHook, drawing: SharedDrawingPayload) {
    this.el.querySelector("#shared-drawing-drawer")!.textContent = drawing.drawer_name;
    this.el.querySelector("#shared-drawing-word")!.textContent = drawing.word;

    this.el.querySelector("[data-shared-drawing-content]")?.classList.remove("hidden");
    this.el.querySelector("[data-shared-drawing-content]")?.classList.add("flex");

    this.events = drawing.events;
    this.replay();
  },
};

export default SharedDrawing;
