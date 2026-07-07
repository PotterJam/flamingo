import { CompactOp, DrawEvent, opsToEvents, replayEvents } from "./drawing_canvas";

type SharedDrawingPayload = {
  drawer_name: string;
  word: string;
  round_number: number;
  events: DrawEvent[];
};

type CompactPayload = {
  v: number;
  n: string;
  w: string;
  r: number;
  o: CompactOp[];
};

interface SharedDrawingHook {
  el: HTMLElement;
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  events: DrawEvent[];
  replayToken: number;
  loadDrawing: () => Promise<void>;
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

const inflate = async (bytes: Uint8Array) => {
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream("deflate"));

  return new Uint8Array(await new Response(stream).arrayBuffer());
};

// Compressed links are prefixed with "z"; anything else is a legacy link
// carrying the raw event list as plain base64url JSON.
const decodeCompressed = async (encoded: string): Promise<SharedDrawingPayload> => {
  const json = new TextDecoder().decode(await inflate(decodeBase64Url(encoded)));
  const payload = JSON.parse<CompactPayload>(json);

  return {
    drawer_name: payload.n,
    word: payload.w,
    round_number: payload.r,
    events: opsToEvents(payload.o),
  };
};

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

  async loadDrawing(this: SharedDrawingHook) {
    const encoded = window.location.hash.slice(1);

    if (!encoded) {
      this.showInvalid();
      return;
    }

    try {
      const drawing = encoded.startsWith("z")
        ? await decodeCompressed(encoded.slice(1))
        : decodeBase64UrlJson(encoded);

      this.showDrawing(drawing);
    } catch {
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
