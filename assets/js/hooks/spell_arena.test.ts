import { expect, test } from "bun:test";
import SpellArena from "./spell_arena";

// Drives the real hook through its public surface: server events in, pointer
// events in, pushEvent commands out, with a fake clock and a no-op canvas.
let now = 0;
Object.defineProperty(globalThis, "performance", { value: { now: () => now }, configurable: true });

const noop = () => {};

function mount(aimMode: "hold" | "drag" | "classic" = "hold") {
  now = 0;
  const saved = new Map([["spellslingers_aim_mode", aimMode]]);
  globalThis.localStorage = {
    getItem: (k: string) => saved.get(k) ?? null,
    setItem: (k: string, v: string) => saved.set(k, v),
  } as never;
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
    hidden: false,
    getElementById: (id: string) => (id === "spellslingers-game" ? { classList: { contains: () => false } } : null),
    body: { classList: { add: noop, remove: noop, toggle: noop } },
    addEventListener: (name: string, f: (event: unknown) => void) => listeners.set(`document:${name}`, f),
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
    keyUp: (key: string) => listeners.get("window:keyup")!({ key }),
    visibility: (hidden: boolean) => {
      Object.assign(document, { hidden });
      listeners.get("document:visibilitychange")!({});
    },
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
  timeline: null,
  players: { me: { name: "Me", color: "#fff" } },
  spells: [spell("firebolt"), spell("fuserune"), spell("slab", { input: "place", gravity: 0 })],
  my_spells: ["firebolt", "fuserune", "slab"],
  selected_spell: "firebolt",
  physics: { dt: 0.04, gravity: 30, max_speed: 80, wind_accel: 1, playback_speed: 2, place_range: 70 },
  ...extra,
});

const cast = (id: number) => ({
  id, caster_id: "me", spell: "broom", segments: [], moves: [], events: [], shake: false, auras: [],
  flight_steps: 20, slow_at: null, beat: null, lead_ms: 0, duration_ms: 900,
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
  a.server("arena_state", state({ timeline: cast(1) }));
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
  a.server("arena_state", state({ timeline: cast(castIds[0]) }));
  a.tick(1);
  for (const id of castIds.slice(1)) a.server("arena_state", state({ timeline: cast(id) }));
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

test("a fall holds the controls until it has played; a crate grabbed in passing does not", () => {
  const timeline = (id: number, extra: Record<string, unknown>) => ({ ...cast(id), spell: null, flight_steps: 0, duration_ms: 1500, ...extra });
  const firstCast = (extra: Record<string, unknown>) => {
    const a = mount();
    a.server("arena_state", state());
    a.tick(1);
    a.server("arena_state", state({ timeline: timeline(1, extra) }));
    for (let t = 10; t < 5000; t += 10) {
      a.tick(t);
      a.down();
      a.up();
      if (casts(a.sent).length) return t;
    }
    return Infinity;
  };
  const fall = { id: "me", kind: "fall", start: 0, path: [[100, 60], [100, 70], [100, 80]] };
  expect(firstCast({ moves: [fall], events: [{ kind: "land", id: "me", at: 2, ms: 1200, hp: 140 }] })).toBeGreaterThanOrEqual(1500);
  expect(firstCast({ events: [{ kind: "crate", crate: "c1", id: "me", at: 0, ms: 0, hp: 150 }] })).toBeLessThan(100);
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
  a.server("arena_state", { ...state({ timeline: { ...cast(7), flight_steps: 451, duration_ms: 12000 } }), full: true });
  a.tick(100);
  a.down();
  now = 500;
  a.up();
  expect(casts(a.sent)).toHaveLength(1);
});

test("casts that land while the tab is hidden are not replayed on coming back", () => {
  const a = mount();
  a.server("arena_state", state({ current_id: "other" }));
  a.tick(1);
  // A hidden tab draws no frames, so nothing plays until it is shown again.
  Object.assign(document, { hidden: true });
  const theirs = (id: number) => ({ ...cast(id), caster_id: "other" });
  a.server("arena_state", state({ phase: "arena_resolve", current_id: "other", timeline: theirs(1) }));
  a.server("arena_state", state({ phase: "arena_resolve", current_id: "other", timeline: theirs(2) }));
  a.server("arena_state", state({ timeline: theirs(2) }));
  Object.assign(document, { hidden: false });
  // Back on the tab a minute later, it is our turn and the arena answers at once.
  a.tick(60000);
  a.down();
  now = 60400;
  a.up();
  expect(casts(a.sent)).toHaveLength(1);
});

test("leaving the tab mid-cast skips the rest of it, here and in the HUD", () => {
  const a = mount();
  a.server("arena_state", state({ current_id: "other" }));
  a.tick(1);
  a.server("arena_state", state({ phase: "arena_resolve", current_id: "other", timeline: { ...cast(3), caster_id: "other", duration_ms: 8000 } }));
  a.tick(100);
  expect(a.sent.filter((e) => e.name === "timeline_started")).toEqual([{ name: "timeline_started", id: 3 }]);
  a.server("arena_state", state({ timeline: { ...cast(3), caster_id: "other", duration_ms: 8000 } }));
  a.visibility(true);
  expect(a.sent.filter((e) => e.name === "timeline_skipped")).toEqual([{ name: "timeline_skipped", id: 3 }]);
  // Back a moment later, long before the cast would have ended: it is our turn at once.
  a.visibility(false);
  a.tick(600);
  a.down();
  now = 1000;
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

test("dragging back throws the opposite way at the pull's power, however long it is held", () => {
  const a = mount("drag");
  a.server("arena_state", state());
  a.tick(1);
  // A full pull is 40% of the 500 px arena's height: 200 px.
  a.down();
  a.move(550, 300);
  a.tick(5000);
  now = 5000;
  a.up();
  const [thrown] = casts(a.sent);
  // Pulled down and left, so it flies up and right; 141 px of 200 is 71%.
  expect(thrown.angle).toBe(45);
  expect(thrown.power).toBeCloseTo(70.7, 1);
});

test("letting go of a pull too short to read throws nothing and keeps the turn", () => {
  const a = mount("drag");
  a.server("arena_state", state());
  a.tick(1);
  a.down();
  a.move(655, 203);
  now = 800;
  a.up();
  expect(casts(a.sent)).toEqual([]);
  a.down();
  a.move(650, 400);
  a.up();
  expect(casts(a.sent).map((e) => [e.angle, e.power])).toEqual([[90, 100]]);
});

test("classic aiming: held arrows turn the crosshair, and a full power bar fires by itself", () => {
  const a = mount("classic");
  a.server("arena_state", state());
  a.tick(1);
  // Facing right, with the crosshair level; Up held 0.7 s lifts it 1 degree, then 70 a second after 0.22 s.
  a.key("d");
  a.keyUp("d");
  a.key("ArrowUp");
  for (let t = 16; t <= 716; t += 16) a.tick(t);
  a.keyUp("ArrowUp");
  a.key(" ");
  // The mouse cannot swing a shot that is already charging.
  a.move(350, 200);
  for (let t = 720; t < 3000; t += 16) a.tick(t);
  const [thrown] = casts(a.sent);
  expect(thrown.power).toBe(100);
  expect(thrown.angle as number).toBeGreaterThan(30);
  expect(thrown.angle as number).toBeLessThan(40);
  // Arrows aim rather than jump.
  expect(a.sent.some((e) => e.name === "jump")).toBe(false);
});

test("classic aiming: turning round mirrors the crosshair, and an early release is a softer shot", () => {
  const a = mount("classic");
  a.server("arena_state", state());
  a.tick(1);
  a.key("d");
  a.keyUp("d");
  a.key("ArrowUp");
  for (let t = 16; t <= 716; t += 16) a.tick(t);
  a.keyUp("ArrowUp");
  a.key("a");
  a.keyUp("a");
  a.key(" ");
  now = 1100;
  a.keyUp(" ");
  const [thrown] = casts(a.sent);
  expect(180 - (thrown.angle as number)).toBeGreaterThan(30);
  expect(180 - (thrown.angle as number)).toBeLessThan(40);
  expect(thrown.power as number).toBeLessThan(50);
});

test("classic aiming: the mouse swings the crosshair, arrow taps fine-tune it a degree each, and a click fires as tuned", () => {
  const fire = (nudges: number, wobble: boolean) => {
    const a = mount("classic");
    a.server("arena_state", state());
    a.tick(1);
    a.move(602, 190);
    for (let i = 0; i < nudges; i++) {
      a.key("ArrowUp");
      a.keyUp("ArrowUp");
    }
    // A small wobble of the mouse keeps the nudges; the click fires where they left it.
    if (wobble) a.move(607, 193);
    for (let t = 16; t < 200; t += 16) a.tick(t);
    a.down();
    now = 900;
    a.up();
    return casts(a.sent)[0].angle as number;
  };
  // Two taps add exactly two degrees to where the mouse pointed, wobble or not.
  expect(fire(2, true) - fire(0, false)).toBeCloseTo(2, 5);
  // Without a nudge, the mouse still aims the crosshair directly.
  expect(fire(0, true)).not.toBe(fire(0, false));
});
