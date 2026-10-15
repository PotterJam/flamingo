import { expect, test } from "bun:test";
import AvatarCustomizer from "./avatar_customizer";

test("avatar strokes follow SVG coordinates and keep taps and pointer lifetimes intact", () => {
  const originalPoint = globalThis.DOMPoint;
  const originalDocument = globalThis.document;
  const originalLocalStorage = globalThis.localStorage;
  const originalSessionStorage = globalThis.sessionStorage;
  // A letterboxed SVG: its origin is (200, 100), at two screen pixels per SVG unit.
  globalThis.DOMPoint = class {
    constructor(public x: number, public y: number) {}
    matrixTransform(matrix: { a: number; d: number; e: number; f: number }) {
      return { x: this.x * matrix.a + matrix.e, y: this.y * matrix.d + matrix.f };
    }
  } as typeof DOMPoint;
  const storage = { getItem: () => null, setItem: () => {} } as unknown as Storage;
  globalThis.localStorage = storage;
  globalThis.sessionStorage = storage;

  const listeners = new Map<string, (event: PointerEvent) => void>();
  const captures = new Set<number>();
  let path = "";
  globalThis.document = {
    createElementNS: () => ({ setAttribute: (name: string, value: string) => {
      if (name === "d") path = value;
    } }),
  } as unknown as Document;
  const rendered = {
    children: [] as Element[],
    setAttribute: () => {},
    append(child: Element) { this.children.push(child); },
  };
  const status = { textContent: "" };
  const surface = {
    querySelector: () => rendered,
    getScreenCTM: () => ({ inverse: () => ({ a: 0.5, d: 0.5, e: -100, f: -50 }) }),
    getBoundingClientRect: () => ({ left: 0, top: 100, width: 660, height: 290 }),
    addEventListener: (name: string, handler: (event: PointerEvent) => void) => listeners.set(name, handler),
    setPointerCapture: (id: number) => captures.add(id),
    hasPointerCapture: (id: number) => captures.has(id),
    releasePointerCapture: (id: number) => captures.delete(id),
  };
  const editor = {
    querySelector: (selector: string) => {
      if (selector === "[data-avatar-drawing-surface]") return surface;
      if (selector === "[data-avatar-drawing-preview]") return { querySelector: () => null };
      return status;
    },
    addEventListener: () => {},
  };
  const form = {
    elements: { namedItem: () => null },
    querySelector: () => null,
    addEventListener: () => {},
  };
  const hook = {
    el: {
      closest: () => form,
      querySelector: (selector: string) => selector === "[data-avatar-drawing-editor]" ? editor : null,
      querySelectorAll: () => [],
      addEventListener: () => {},
    },
  } as unknown as ThisParameterType<typeof AvatarCustomizer.mounted>;
  const pointer = (type: string, x: number, y: number, extra = {}) => listeners.get(type)!({
    type, clientX: x, clientY: y, pointerId: 1, isPrimary: true, button: 0,
    preventDefault() {}, ...extra,
  } as PointerEvent);

  try {
    AvatarCustomizer.mounted.call(hook);
    hook.drawingPart = "head";
    pointer("pointerdown", 270, 160); // SVG (35, 30), not the centre of the viewBox.
    expect(path).toBe("M 35 30 L 35 30");
    pointer("pointerdown", 310, 190, { pointerId: 2, isPrimary: false });
    pointer("pointermove", 310, 190, { pointerId: 2 });
    expect(path).toBe("M 35 30 L 35 30");
    pointer("pointermove", 290.5, 180.5);
    pointer("pointerup", 300, 190);
    expect(path).toBe("M 35 30 L 35 30 L 45.3 40.3 L 50 45");
    pointer("pointermove", 320, 200);
    expect(hook.drawingStrokes).toHaveLength(1);
    expect(path.endsWith("L 50 45")).toBe(true);

    pointer("pointerdown", 20, 160); // Letterbox gutter must not draw on the guide edge.
    pointer("pointerdown", 270, 160, { button: 2 });
    expect(hook.drawingStrokes).toHaveLength(1);
    pointer("pointerdown", 310, 190);
    pointer("pointercancel", 0, 0);
    pointer("pointermove", 320, 200);
    expect(path.endsWith("M 55 45 L 55 45")).toBe(true);
    pointer("pointerdown", 330, 200);
    pointer("lostpointercapture", 0, 0);
    pointer("pointermove", 340, 210);
    expect(path.endsWith("M 65 50 L 65 50")).toBe(true);

    hook.drawingPart = "feet";
    pointer("pointerdown", 232, 386); // Bottom-left edge: inset the entire outlined brush.
    pointer("pointermove", 600, 600);
    pointer("pointerup", 600, 600);
    expect(path).toBe("M 21 138 L 21 138 L 103 138");

    hook.drawingStrokes = [{ path: "M 30 135" + " L 40 135".repeat(2661), width: 6 }];
    const saved = JSON.stringify(hook.drawingStrokes);
    expect(saved.length).toBeLessThanOrEqual(24_000);
    pointer("pointerdown", 280, 370);
    expect(status.textContent).toContain("Drawing is full");
    expect(JSON.stringify(hook.drawingStrokes)).toBe(saved);
  } finally {
    globalThis.DOMPoint = originalPoint;
    globalThis.document = originalDocument;
    globalThis.localStorage = originalLocalStorage;
    globalThis.sessionStorage = originalSessionStorage;
  }
});
