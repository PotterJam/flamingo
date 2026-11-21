import { expect, test } from "bun:test";
import SpellArena from "./spell_arena";

// Drives the real hook through its public surface: server events in, pointer
// events in, pushEvent commands out, with a fake clock and a no-op canvas.
let now = 0;
Object.defineProperty(globalThis, "performance", { value: { now: () => now }, configurable: true });

const noop = () => {};

function mount() {
  now = 0;
  const listeners = new Map<string, (event: unknown) => void>();
  const events = new Map<string, (payload: unknown) => void>();
  const sent: Record<string, unknown>[] = [];
  let frame: FrameRequestCallback = noop;
  const gradient = { addColorStop: noop };
  const ctx = new Proxy(
    {
      createImageData: (w: number, h: number) => ({ data: new Uint8ClampedArray(w * h * 4) }),
      createLinearGradient: () => gradient,
      createRadialGradient: () => gradient,
    } as Record<string | symbol, unknown>,
    { get: (o, k) => (k in o ? o[k] : noop) },
  );
  const canvas = {
    width: 1000,
    height: 500,
    clientWidth: 1000,
    getContext: () => ctx,
    focus: noop,
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 1000, height: 500 }),
    addEventListener: (name: string, f: (event: unknown) => void) => listeners.set(name, f),
    removeEventListener: noop,
  };
  globalThis.window = {
    __soundVolume: 0,
    devicePixelRatio: 1,
    addEventListener: (name: string, f: (event: unknown) => void) => listeners.set(`window:${name}`, f),
    removeEventListener: noop,
  } as never;
  globalThis.document = {
    getElementById: () => ({}),
    addEventListener: noop,
    removeEventListener: noop,
    createElement: () => canvas,
  } as never;
  globalThis.ResizeObserver = class {
    observe() {}
    disconnect() {}
  } as never;
  globalThis.requestAnimationFrame = (f) => {
    frame = f;
    return 1;
  };
  globalThis.cancelAnimationFrame = noop;

  const hook = {
    el: canvas,
    pushEvent: (name: string, payload: object) => sent.push({ name, ...payload }),
    handleEvent: (name: string, f: (payload: unknown) => void) => events.set(name, f),
    js: () => ({ addClass: noop, removeClass: noop }),
  };
  SpellArena.mounted.call(hook as never);

  const pointer = (name: string, x = 650, y = 200) =>
    listeners.get(name)!({ button: 0, pointerId: 1, clientX: x, clientY: y, preventDefault: noop });

  return {
    sent,
    server: (name: string, payload: unknown) => events.get(name)!(payload),
    tick(t: number) {
      now = t;
      frame(t);
    },
    down: () => pointer("pointerdown"),
    move: () => pointer("pointermove"),
    up: () => listeners.get("window:pointerup")!({}),
    cancel: () => listeners.get("pointercancel")?.({ pointerId: 1 }),
    blur: () => listeners.get("window:blur")?.({}),
  };
}

const spell = (id: string, extra = {}) => ({
  id, name: id, effect: "blast", gravity: 1, wind: 1, speed: 1, radius: 5, quick: false, place: false, ...extra,
});

// Solid ground from row 61 down, under the wizard standing at y = 60.
const ground = (() => {
  const bytes = new Uint8Array(3750);
  for (let i = 61 * 300; i < 300 * 100; i++) bytes[i >> 3] |= 1 << (7 - (i & 7));
  return Buffer.from(bytes).toString("base64");
})();

const state = (extra: Record<string, unknown> = {}) => ({
  phase: "arena_aim",
  viewer_id: "me",
  current_id: "me",
  participation: "active",
  map_id: "isles",
  wind: 0,
  width: 300,
  height: 100,
  water_level: 95,
  terrain: ground,
  units: [{ id: "me", kind: "wizard", owner: "me", x: 100, y: 60, hp: 100, max_hp: 100, dead: false }],
  crates: [],
  last_cast: null,
  players: { me: { name: "Me", color: "#fff" } },
  spells: [spell("ember"), spell("boulder"), spell("golem", { place: true, gravity: 0 })],
  my_spells: ["ember", "boulder", "golem"],
  selected_spell: "ember",
  physics: { dt: 0.04, gravity: 30, max_speed: 80, wind_accel: 1, playback_speed: 2, place_range: 70 },
  ...extra,
});

const cast = (id: number) => ({
  id, caster_id: "me", spell: "ward", segments: [], beams: [], knocks: [], shake: false, auras: [], ko: [],
  flight_steps: 20, duration_ms: 900,
});

const casts = (sent: Record<string, unknown>[]) => sent.filter((e) => e.name === "cast" || e.name === "place");

test("a charged cast names the spell that was selected when the charge began", () => {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_select", { spell: "boulder" });
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["boulder"]);
});

test("a selection made while a cast plays survives the cast's older snapshot", () => {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_state", state({ last_cast: cast(1) }));
  a.server("arena_select", { spell: "boulder" });
  a.tick(1);
  a.tick(5000);
  a.tick(10000);
  a.down();
  now = 10400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["boulder"]);
});

test("the server can still move the selection, e.g. off a spell on cooldown", () => {
  const a = mount();
  a.server("arena_state", state({ selected_spell: "boulder" }));
  a.server("arena_state", state({ selected_spell: "ember" }));
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["ember"]);
});

// How long until a click casts again, after the given casts arrive while the
// first one is playing.
function unlockAfter(castIds: number[]) {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_state", state({ last_cast: cast(castIds[0]) }));
  a.tick(1);
  for (const id of castIds.slice(1)) a.server("arena_state", state({ last_cast: cast(id) }));
  for (let t = 10; t < 20000; t += 10) {
    a.tick(t);
    a.down();
    a.up();
    if (casts(a.sent).length) return t;
  }
  return Infinity;
}

test("a cast arriving while another plays is played too, keeping controls locked", () => {
  const one = unlockAfter([1]);
  expect(one).toBeLessThan(20000);
  expect(unlockAfter([1, 2])).toBeGreaterThan(one + 200);
  // A refreshed snapshot of the same cast is not a second cast.
  expect(unlockAfter([1, 1])).toBe(one);
});

test("a cancelled pointer drops the charge instead of firing at full power", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  a.cancel();
  a.tick(1400);
  a.tick(3000);
  expect(casts(a.sent)).toEqual([]);
});

test("losing window focus drops the charge", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  a.blur();
  a.tick(3000);
  expect(casts(a.sent)).toEqual([]);
});

test("a first tap places a placed spell without any hover", () => {
  const a = mount();
  a.server("arena_state", state({ selected_spell: "golem" }));
  a.tick(1);
  a.down();
  expect(casts(a.sent).map((e) => [e.name, e.spell])).toEqual([["place", "golem"]]);
});
