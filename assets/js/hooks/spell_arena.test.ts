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
      measureText: () => ({ width: 0 }),
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
    getElementById: (id: string) => (id === "spellslingers-game" ? { classList: { contains: () => false } } : null),
    body: { classList: { add: noop, remove: noop, toggle: noop } },
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

  const pointer = (name: string, x = 650, y = 200, button = 0) =>
    listeners.get(name)!({ button, pointerId: 1, clientX: x, clientY: y, preventDefault: noop });

  return {
    sent,
    server: (name: string, payload: unknown) => events.get(name)!(payload),
    tick(t: number) {
      now = t;
      frame(t);
    },
    down: () => pointer("pointerdown"),
    move: (x?: number, y?: number) => pointer("pointermove", x, y),
    rightClick: () => pointer("pointerdown", 650, 200, 2),
    up: () => listeners.get("window:pointerup")!({}),
    cancel: () => listeners.get("pointercancel")?.({ pointerId: 1 }),
    blur: () => listeners.get("window:blur")?.({}),
    key: (key: string) =>
      listeners.get("window:keydown")!({ key, repeat: false, target: null, metaKey: false, ctrlKey: false, preventDefault: noop }),
  };
}

const spell = (id: string, extra = {}) => ({
  id, name: id, effect: "blast", gravity: 1, wind: 1, speed: 1, radius: 5, input: "charge", color: "#f97316", ...extra,
});

// Solid ground from row 61 down, under the wizard standing at y = 60.
const ground = (() => {
  const bytes = new Uint8Array(3750);
  for (let i = 61 * 300; i < 300 * 100; i++) bytes[i >> 3] |= 1 << (7 - (i & 7));
  return btoa(String.fromCharCode(...bytes));
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
  walk_left: 40,
  terrain: ground,
  units: [{ id: "me", kind: "wizard", owner: "me", x: 100, y: 60, hp: 150, max_hp: 150, dead: false }],
  crates: [],
  last_cast: null,
  players: { me: { name: "Me", color: "#fff" } },
  spells: [spell("firebolt"), spell("fuserune"), spell("slab", { input: "place", gravity: 0 })],
  my_spells: ["firebolt", "fuserune", "slab"],
  selected_spell: "firebolt",
  physics: { dt: 0.04, gravity: 30, max_speed: 80, wind_accel: 1, playback_speed: 2, place_range: 70 },
  ...extra,
});

const cast = (id: number) => ({
  id, caster_id: "me", spell: "broom", segments: [], knocks: [], shake: false, auras: [], ko: [],
  flight_steps: 20, duration_ms: 900,
});

const casts = (sent: Record<string, unknown>[]) => sent.filter((e) => e.name === "cast" || e.name === "place");

test("a charged cast names the spell that was selected when the charge began", () => {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_select", { spell: "fuserune" });
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["fuserune"]);
});

test("a selection made while a cast plays survives the cast's older snapshot", () => {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_state", state({ last_cast: cast(1) }));
  a.server("arena_select", { spell: "fuserune" });
  a.tick(1);
  a.tick(5000);
  a.tick(10000);
  a.down();
  now = 10400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["fuserune"]);
});

test("the server can still move the selection, e.g. off a spell on cooldown", () => {
  const a = mount();
  a.server("arena_state", state({ selected_spell: "fuserune" }));
  a.server("arena_state", state({ selected_spell: "firebolt" }));
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["firebolt"]);
});

test("after casting a picked spell that then cools down, the selection falls back to the server's pick", () => {
  const a = mount();
  a.server("arena_state", state());
  a.server("arena_select", { spell: "fuserune" });
  // The cast put Fuse Rune out of ammo, so the server moved the selection back to Firebolt.
  a.server("arena_state", state({ selected_spell: "firebolt" }));
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  expect(casts(a.sent).map((e) => e.spell)).toEqual(["firebolt"]);
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

test("a charge does not outlive the turn it started in", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  a.server("arena_state", state({ current_id: "other" }));
  a.tick(1500);
  a.server("arena_state", state());
  a.tick(10000);
  expect(casts(a.sent)).toEqual([]);
});

test("a first tap places a placed spell without any hover", () => {
  const a = mount();
  a.server("arena_state", state({ selected_spell: "slab" }));
  a.tick(1);
  a.down();
  expect(casts(a.sent).map((e) => [e.name, e.spell])).toEqual([["place", "slab"]]);
});

test("a rejoin shows the board as it is instead of replaying a cast it missed", () => {
  const a = mount();
  a.server("arena_state", state({ current_id: "other" }));
  a.tick(1);
  // After a reconnect the LiveView remounts and sends a full snapshot, catalog
  // included, whose last cast already resolved and whose turn is now ours.
  a.server("arena_state", { ...state({ last_cast: { ...cast(7), flight_steps: 451, duration_ms: 12000 } }), full: true });
  a.tick(100);
  a.down();
  now = 500;
  a.up();
  expect(casts(a.sent)).toHaveLength(1);
});

test("arrow keys walk, jump and float exactly like WASD, and jumps go the way the wizard last faced", () => {
  const a = mount();
  const moves = (keys: string[]) =>
    keys.map((key) => {
      now += 100;
      a.key(key);
      const last = a.sent.at(-1)!;
      return [last.name, last.kind ?? last.dir, last.kind ? last.dir : undefined];
    });
  a.server("arena_state", state());
  a.tick(1);
  // Standing on the left half, a wizard that has not moved faces right.
  const standing = [["jump", "high", 1], ["walk", -1, undefined], ["jump", "high", -1], ["jump", "long", -1], ["walk", 1, undefined], ["jump", "long", 1]];
  expect(moves(["w", "a", "w", "s", "d", "s"])).toEqual(standing);
  expect(moves(["ArrowUp", "ArrowLeft", "ArrowUp", "ArrowDown", "ArrowRight", "ArrowDown"])).toEqual(standing);

  // While levitating the same keys float up and down instead.
  const floating = state({ units: [{ ...state().units[0], float: 2 }] });
  a.server("arena_state", floating);
  a.tick(now + 1);
  expect(moves(["w", "s", "ArrowUp", "ArrowDown"])).toEqual([["rise", 1, undefined], ["rise", -1, undefined], ["rise", 1, undefined], ["rise", -1, undefined]]);
});

test("full power waits for the release instead of firing itself", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  a.tick(5000);
  expect(casts(a.sent)).toEqual([]);
  now = 5000;
  a.up();
  expect(casts(a.sent).map((e) => e.power)).toEqual([100]);
});

test("the aim follows the mouse while charging", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  // From up-and-right of the wizard to up-and-left of it.
  a.move(350, 200);
  now = 400;
  a.up();
  const [thrown] = casts(a.sent);
  expect(thrown.angle as number).toBeGreaterThan(90);
});

test("a right-click or Esc cancels a charge and the release then casts nothing", () => {
  for (const cancel of ["right", "esc"]) {
    const a = mount();
    a.server("arena_state", state());
    a.tick(1);
    a.down();
    if (cancel === "right") a.rightClick();
    else a.key("Escape");
    now = 800;
    a.up();
    a.tick(3000);
    expect(casts(a.sent)).toEqual([]);
    // Still this player's turn: the next charge throws.
    a.down();
    now = 1200;
    a.up();
    expect(casts(a.sent).length).toBe(1);
  }
});

test("holding D walks at a steady pace without key repeat, and stops at a wall too tall to climb", () => {
  // The ground from row 61 down, plus a wall at x = 104 rising to row 50.
  const bytes = Uint8Array.from(atob(ground), (c) => c.charCodeAt(0));
  for (let y = 50; y <= 60; y++) bytes[(y * 300 + 104) >> 3] |= 1 << (7 - ((y * 300 + 104) & 7));
  const walled = btoa(String.fromCharCode(...bytes));
  // A one-cell step at x = 101 is climbed rather than blocking.
  const stepped = Uint8Array.from(atob(walled), (c) => c.charCodeAt(0));
  for (let x = 101; x < 104; x++) stepped[(60 * 300 + x) >> 3] |= 1 << (7 - ((60 * 300 + x) & 7));

  const a = mount();
  a.server("arena_state", state({ terrain: btoa(String.fromCharCode(...stepped)) }));
  a.tick(1);
  a.key("d");
  for (let t = 2; t < 2000; t += 16) a.tick(t);
  const walks = a.sent.filter((e) => e.name === "walk");
  // Three steps (101, 102, 103), then the wall: nothing more is sent.
  expect(walks).toEqual([1, 1, 1].map((dir) => ({ name: "walk", dir })));
});

test("on a broomstick a held key flies on until the broom's fuel, not the turn's walk, runs out", () => {
  const a = mount();
  a.server("arena_state", state());
  a.tick(1);
  // Mounting the broom mid-turn tops the steps up from 40 to 80.
  a.server("arena_state", state({ walk_left: 80, units: [{ ...state().units[0], float: 1 }] }));
  a.tick(2);
  a.key("d");
  for (let t = 3; t < 6000; t += 16) a.tick(t);
  expect(a.sent.filter((e) => e.name === "walk")).toHaveLength(80);
});

test("during the retreat after a cast the wizard still walks, but casts nothing", () => {
  const a = mount();
  a.server("arena_state", state({ retreat: true }));
  a.tick(1);
  a.down();
  now = 400;
  a.up();
  a.key("d");
  for (let t = 2; t < 300; t += 16) a.tick(t);
  expect(casts(a.sent)).toEqual([]);
  expect(a.sent.some((e) => e.name === "walk")).toBe(true);
});
