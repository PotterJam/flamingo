import { createSpellSounds } from "./spell_sounds";
import { BOOM_CELL, BOOM_FRAMES, CRATE_FRAME, CRATE_SIZE, LAND_RES, SPELL_CELL, WINGTIP, WIZARD, WIZARD_H, WIZARD_W, carveLand, loadArt, paintLand, poseRig, ready, RIG, rigTip, wizardSheet } from "./arena_art";

// Renders the Spellslingers arena: destructible terrain, wizards, crates, blast runes, aiming,
// and the playback of each cast. The server owns every rule and all physics; this hook
// only draws its snapshots, animates the flight and knockback paths the server computed,
// and turns pointer and keyboard input into commands.


type Unit = {
  id: string;
  kind: "wizard";
  owner: string;
  x: number;
  y: number;
  hp: number;
  max_hp: number;
  dead: boolean;
  // Turns left on a broomstick: a floating wizard hovers and flies.
  float?: number;
};

type Crate = { id: string; type: "health" | "mana"; x: number; y: number };

type Spell = {
  id: string;
  name: string;
  effect: string;
  gravity: number;
  wind: number;
  speed: number;
  radius: number;
  // How the player aims it, and the colour it is drawn in; both come from the server catalog.
  input: "charge" | "beam" | "place" | "instant";
  color: string;
  // Grand spells are the big set pieces; sky spells strike anywhere from above.
  grand?: boolean;
  sky?: boolean;
  // Its frame in the spells sheet, and how far a beam reaches (null: across the map).
  sprite: number;
  range?: number | null;
};

// A Nest Egg waiting where it rolled to for its caster's turn to end: (x, y) is its
// middle, and `spin` how far it turned rolling there.
type Rune = { owner: string; x: number; y: number; spin?: number };

// The shot a bot is lining up, shown before it fires.
type BotAim = { spell: string; angle?: number; power?: number; x?: number; y?: number };

type Segment = { path: [number, number][]; start: number; spell: string; radius: number; hit: boolean };

type Hit = { id: string; at: number; hp: number };

type Cast = {
  id: number;
  caster_id: string | null;
  spell: string;
  segments: Segment[];
  // Each unit struck, at the step it is struck, with the health it is left with.
  hits?: Hit[];
  knocks: { id: string; path: [number, number][] }[];
  shake: boolean;
  grand?: boolean;
  auras: { id: string; kind: string }[];
  ko: string[];
  flight_steps: number;
  duration_ms: number;
};

type ArenaState = {
  phase: string;
  viewer_id: string;
  current_id: string | null;
  // Everyone in the duel, in turn order.
  player_order?: string[];
  participation: string;
  map_id: string;
  wind: number;
  width: number;
  height: number;
  water_level: number;
  terrain: string;
  units: Unit[];
  crates: Crate[];
  runes?: Rune[];
  // After a cast the wizard may still move for a few seconds, but not cast.
  retreat?: boolean;
  bot_aim?: BotAim | null;
  last_cast: Cast | null;
  players: Record<string, { name: string; color: string }>;
  spells: Spell[];
  my_spells: string[];
  selected_spell: string;
  // The latest jump, numbered so each one plays once; its path is in unit cells.
  last_jump: { n: number; id: string; path: [number, number][] } | null;
  physics: { dt: number; gravity: number; max_speed: number; wind_accel: number; playback_speed: number; place_range: number; grand_intro_ms?: number; intro_step_ms?: number; max_climb?: number; egg_radius?: number };
  // Steps left this turn, for walking ahead of the server.
  walk_left?: number;
};

type Floater = { x: number; y: number; text: string; color: string; size: number; life: number; max: number };

type Particle = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  max: number;
  color: string;
  size: number;
  chunk?: boolean;
  // A clod's outline, as radii around it, and how often it has hit the ground.
  shape?: number[];
  bounces?: number;
  rot?: number;
};

// The leftovers of a blast: a flash ring that races out, and smoke that drifts with the wind.
type Ring = { x: number; y: number; r: number; born: number; color: string };
type Smoke = { x: number; y: number; r: number; vx: number; vy: number; life: number; max: number };

type Animation = {
  cast: Cast;
  start: number;
  // Segments that have already burst on impact.
  landed: Set<number>;
  // When the projectiles finished and the post-cast state took over.
  aftermathAt: number | null;
  // Hits not yet shown, soonest first.
  hits: Hit[];
  // Knocked-out wizards already shown falling, and when the first one fell.
  koShown: Set<string>;
  koAt: number | null;
};

interface SpellArenaHook {
  el: HTMLCanvasElement;
  pushEvent: (event: string, payload: object) => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
  // LiveView's sticky JS commands, so what they show and hide survives server patches.
  js: () => {
    show: (el: HTMLElement, opts?: { display?: string }) => void;
    hide: (el: HTMLElement) => void;
    toggle: (el: HTMLElement, opts?: { display?: string }) => void;
  };
  cleanup?: () => void;
}

// Wild-magic meteors are not a spell, so they have no catalog colour.
const SURGE_COLOR = "#f43f5e";

type Palette = {
  sky: [string, string, string];
  hills: string;
  water: string;
  grass: [number, number, number][];
  soil: [number, number, number][];
  rock: [number, number, number][];
};

// Each mine's colours: the sky above the painted backdrop, the crust along the top of
// the land, the clods a blast throws, and its murky water.
const PALETTES: Record<string, Palette> = {
  isles: {
    sky: ["#a77a9e", "#e3948c", "#f4bd8c"],
    hills: "#c98a8a",
    water: "rgba(64, 160, 164, 0.82)",
    grass: [[150, 178, 82], [108, 138, 58], [72, 98, 42]],
    soil: [[74, 58, 44], [54, 44, 36]],
    rock: [[116, 74, 40], [42, 38, 36], [92, 82, 72]],
  },
  flamingo: {
    sky: ["#c9607e", "#e08aa0", "#f0b096"],
    hills: "#b46a7a",
    water: "rgba(110, 86, 104, 0.8)",
    grass: [[222, 160, 158], [184, 116, 120], [140, 82, 90]],
    soil: [[192, 132, 132], [160, 104, 108]],
    rock: [[214, 160, 170], [120, 80, 84], [170, 120, 124]],
  },
  castles: {
    sky: ["#c0707a", "#e8906a", "#f6c07a"],
    hills: "#c9886e",
    water: "rgba(80, 150, 160, 0.84)",
    grass: [[150, 172, 90], [110, 132, 64], [76, 96, 46]],
    soil: [[122, 102, 90], [96, 84, 76]],
    rock: [[142, 72, 52], [70, 64, 60], [112, 100, 92]],
  },
  cavern: {
    sky: ["#1a1434", "#2a2152", "#3b2c6b"],
    hills: "#2a2152",
    water: "rgba(40, 150, 140, 0.72)",
    grass: [[132, 226, 214], [74, 164, 172], [52, 112, 132]],
    soil: [[72, 62, 102], [56, 48, 84]],
    rock: [[52, 44, 74], [40, 34, 60], [104, 222, 210]],
  },
  archipelago: {
    sky: ["#6b857c", "#9fb0a2", "#c9cbb4"],
    hills: "#7f8f7c",
    water: "rgba(64, 112, 104, 0.82)",
    grass: [[156, 150, 82], [116, 118, 58], [84, 90, 44]],
    soil: [[178, 128, 60], [150, 106, 48]],
    rock: [[122, 104, 84], [96, 70, 50], [152, 130, 100]],
  },
};

function decodeTerrain(encoded: string, width: number, height: number) {
  const bytes = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  const cells = new Uint8Array(width * height);
  for (let i = 0; i < cells.length; i++) cells[i] = (bytes[i >> 3] >> (7 - (i & 7))) & 1;
  return cells;
}

function hash(x: number, y: number) {
  const n = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return n - Math.floor(n);
}

function terrainImage(cells: Uint8Array, width: number, height: number, palette: Palette) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d")!;
  const image = ctx.createImageData(width, height);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      if (!cells[i]) continue;

      let depth = 0;
      while (depth < 5 && y - depth - 1 >= 0 && cells[i - (depth + 1) * width]) depth++;
      const n = hash(x, y);
      let rgb: [number, number, number];

      if (depth === 0) rgb = palette.grass[n > 0.5 ? 0 : 1];
      else if (depth === 1) rgb = palette.grass[2];
      else if (depth < 5) rgb = palette.soil[n > 0.6 ? 0 : 1];
      else rgb = palette.rock[n > 0.93 ? 2 : n > 0.45 ? 0 : 1];

      image.data.set([...rgb, 255], i * 4);
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

const SpellArena = {
  mounted(this: SpellArenaHook) {
    const canvas = this.el;
    const ctx = canvas.getContext("2d")!;
    // W and H are the arena's drawing units; the backing store follows the
    // canvas's on-screen size so text and sprites stay sharp when it grows.
    // W stays fixed; H follows the canvas's shape, so a taller full view shows more
    // of the world (or the sky or rock beyond it) instead of a band of flat colour.
    const W = canvas.width;
    let H = canvas.height;
    let pixelScale = 1;
    const fitResolution = () => {
      const k = Math.min(4, Math.max(1, (canvas.clientWidth * window.devicePixelRatio) / W));
      const h = canvas.clientWidth ? Math.round(W * Math.max(0.5, canvas.clientHeight / canvas.clientWidth)) : H;
      if (Math.abs(k - pixelScale) < 0.05 && h === H) return;
      pixelScale = k;
      H = h;
      fitView();
      canvas.width = Math.round(W * k);
      canvas.height = Math.round(H * k);
    };
    const resizeObserver = new ResizeObserver(fitResolution);
    resizeObserver.observe(canvas);

    // The page already fills the window; F or the menu asks the browser for real
    // fullscreen, and Esc leaves it the way it does everywhere else.
    const root = document.documentElement;
    const toggleFull = () =>
      document.fullscreenElement ? document.exitFullscreen?.() : root?.requestFullscreen?.().catch(() => {});
    canvas.addEventListener("arena:fullscreen", toggleFull);

    // Panels LiveView renders hidden; shown and hidden through LiveView's JS so a
    // patch keeps them as they are.
    const panel = (id: string) => document.getElementById(id);
    const isOpen = (el: HTMLElement | null) => !!el && getComputedStyle(el).display !== "none";
    const hidePanel = (id: string) => {
      const el = panel(id);
      if (!isOpen(el)) return false;
      this.js().hide(el!);
      return true;
    };
    const toggleSpells = () => {
      const el = panel("arena-spells");
      if (!el) return;
      hidePanel("arena-menu");
      this.js().toggle(el, { display: "block" });
    };
    canvas.addEventListener("arena:spells", toggleSpells);

    // The overlays drawn over the arena (wizard rail, chronicle, spell dock) stay out of
    // the way: they turn to ghosts while a spell charges and dim when the pointer comes
    // near without touching them. Body classes, so LiveView patches leave them alone.
    const body = document.body;
    const OVERLAYS: [string, string][] = [
      ["teams", "arena-teams"],
      ["ticker", "arena-ticker"],
    ];
    const NEAR_PX = 36;
    const dimNear = (x: number, y: number) => {
      const area = canvas.getBoundingClientRect();
      for (const [key, id] of OVERLAYS) {
        const r = document.getElementById(id)?.getBoundingClientRect();
        const over = !!r && r.width > 0 && r.top < area.bottom && r.bottom > area.top;
        const inside = over && x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
        const near =
          over && !inside && !charge &&
          x > r.left - NEAR_PX && x < r.right + NEAR_PX && y > r.top - NEAR_PX && y < r.bottom + NEAR_PX;
        body.classList.toggle(`arena-near-${key}`, near);
      }
    };
    const undim = () => OVERLAYS.forEach(([key]) => body.classList.remove(`arena-near-${key}`));

    // While charging, the spell chip in the HUD becomes the power meter. The HUD only
    // renders once the match starts, after this hook mounts, so look it up each time.
    const meterPart = (name: string) =>
      document.getElementById("arena-meter")?.querySelector<HTMLElement>(`[data-meter-${name}]`);
    let chargingShown = false;
    let lastThrow: number | null = null;
    let thrownUntil = 0;
    const syncChargeUi = (now: number) => {
      if (!!charge !== chargingShown) {
        chargingShown = !!charge;
        body.classList.toggle("arena-charging", chargingShown);
        // The hum lasts exactly as long as the charge, however it ends.
        stopChargeSound?.();
        stopChargeSound = charge ? sounds.charge(charge.spell, CHARGE_MS) : null;
        if (charge) {
          undim();
          const meterName = meterPart("name");
          const meterLast = meterPart("last");
          if (meterName) meterName.textContent = spellById(charge.spell)?.name ?? "";
          if (meterLast) {
            meterLast.hidden = lastThrow === null;
            meterLast.style.left = `${lastThrow ?? 0}%`;
          }
        }
      }
      const meterFill = meterPart("fill");
      const meterText = meterPart("text");
      if (charge && meterFill && meterText) {
        const power = chargePower(now);
        meterFill.style.width = `${power}%`;
        meterText.textContent = power >= 100 ? "MAX" : `${Math.round(power)}%`;
      }
      body.classList.toggle("arena-thrown", now < thrownUntil);
    };

    const sky = document.getElementById("arena-sky");

    let shown: ArenaState | null = null;
    // The state the current animation leads to, and states carrying later casts
    // that arrived while it played; each of those plays in turn.
    let pending: ArenaState | null = null;
    const backlog: ArenaState[] = [];
    let terrainCanvas: HTMLCanvasElement | null = null;
    // Pixels per cell in terrainCanvas: the painted land once its texture has loaded,
    // one flat pixel per cell until then.
    let terrainRes = 1;
    let landDirty = false;
    const art = loadArt((name) => {
      // Only this arena's own ground changes how its land is painted.
      if (name === `tex_${shown?.map_id}`) landDirty = true;
    });
    // A veil covers the arena until its art is in (or VEIL_MAX_MS passes, for art that
    // never arrives), and the server hears once per duel that this page is ready.
    const veil = document.getElementById("arena-veil");
    const veilFill = veil?.querySelector<HTMLElement>("[data-veil-fill]");
    const VEIL_MAX_MS = 20000;
    let veilSince = performance.now();
    let veilMap: string | null = null;
    let lifted = false;
    let reported = false;
    // A new duel's intro, from when this page started it: each flamingo drops in, in turn
    // order, while the camera visits it. Until it has dropped in, it isn't drawn at all.
    let introAt: number | null = null;
    const spawned = new Set<string>();
    const SPAWN_DROP_MS = 420;
    const SPAWN_HEIGHT = 34;
    const introStep = () => shown?.physics.intro_step_ms ?? 900;
    const introOrder = () =>
      (shown?.player_order ?? []).filter((id) => shown!.units.some((u) => u.id === id && !u.dead));
    const spawnAt = (id: string) => {
      const i = introOrder().indexOf(id);
      return shown?.phase !== "arena_intro" || introAt === null || i < 0 ? null : introAt + i * introStep() + 150;
    };
    const unspawned = (id: string, now: number) => {
      if (shown?.phase === "arena_loading") return true;
      const at = spawnAt(id);
      return at !== null && now < at;
    };
    // When each unit was last hurt, so it flinches.
    const hurtAt = new Map<string, number>();
    let terrainKey = "";
    let seenCastId = -1;
    let animation: Animation | null = null;
    let particles: Particle[] = [];
    let floaters: Floater[] = [];
    let selected = "firebolt";
    let serverSelected: string | null = null;
    let aim: { angle: number; power: number } | null = null;
    let castLocked = false;
    // Walking runs here first: while A or D is held the wizard steps at a steady pace
    // by the server's own rules (`Units.step` and `settle`), and each step is sent for
    // the server to confirm. Until it has, the predicted spot is where the wizard is drawn.
    const STEP_MS = 95;
    // On a broomstick the wizard flies twice as fast, in any of eight directions while
    // the keys are held: W and S set the climb, A and D the heading.
    const FLY_MS = 50;
    let heldDir = 0;
    let heldV = 0;
    let nextStepAt = 0;
    let predicted: { x: number; y: number; at: number } | null = null;
    let stepsLeft = 0;
    let crouchAt = -1e9;
    // Which way the viewer's wizard faces: the last way it walked or aimed. Jumps go this way.
    let facing = 0;
    let seenJump = -1;
    let jumping: { id: string; path: [number, number][]; start: number } | null = null;
    // Fall damage the server has dealt that shows once the flamingo lands, by id, and
    // flamingos whose drop ends in the sea: they fall all the way before the KO.
    const fallHurt = new Map<string, number>();
    const fallKO = new Set<string>();
    let lastBlockedHint = 0;
    let frame = 0;
    let shakeUntil = 0;
    let shakePower = 0;
    // A grand spell's moment: when its title card started, and the white flash on impact.
    let grand: { start: number; name: string; color: string } | null = null;
    let flashUntil = 0;
    // Glowing rims a grand blast leaves behind, cooling over a few seconds.
    let scars: { x: number; y: number; r: number; born: number }[] = [];
    let rings: Ring[] = [];
    // Painted explosions playing out, each its size across in screen pixels.
    let booms: { x: number; y: number; size: number; born: number; flip: number }[] = [];
    let smokes: Smoke[] = [];
    // Where blasts have scorched the land, burned into it each time it is repainted.
    let scorches: { x: number; y: number; r: number }[] = [];
    // A quick zoom punch on impact, decaying back to nothing. It eases up to its size over
    // PUNCH_RISE ms rather than jumping there in one frame, and a second impact while one
    // is still showing only tops it up to the bigger of the two instead of stacking.
    const PUNCH_RISE = 90;
    let punch = { from: 0, to: 0, at: -1e9 };
    const punchAt = (now: number) => {
      const t = Math.max(0, now - punch.at);
      if (t >= PUNCH_RISE) return punch.to * Math.exp(-(t - PUNCH_RISE) / 110);
      const k = t / PUNCH_RISE;
      return punch.from + (punch.to - punch.from) * k * k * (3 - 2 * k);
    };
    const kick = (size: number) => {
      const now = performance.now();
      const level = punchAt(now);
      if (size > level) punch = { from: level, to: size, at: now };
    };
    // Health bars over units drain to the new value a beat after a hit.
    const bars = new Map<string, { v: number; since: number }>();
    const sounds = createSpellSounds(() => (Number.isFinite(window.__soundVolume) ? window.__soundVolume : 100) / 100);
    let stopChargeSound: (() => void) | null = null;

    // The canvas is a 200 x 100 cell window onto a wider world; the camera pans it.
    // Zoom scales the whole world, wizards and text included; the wheel changes it and
    // the view pulls back a little while a throw charges.
    const CELL = W / 200;
    const ZOOM_MIN = 0.7;
    const ZOOM_MAX = 2.6;
    let zoomTarget = 1.6;
    let zoom = zoomTarget;
    let VIEW_W = 0;
    let VIEW_H = 0;
    const fitView = () => {
      VIEW_W = W / (CELL * zoom);
      VIEW_H = H / (CELL * zoom);
    };
    fitView();
    // World rows hidden behind the spell dock at the bottom of the arena. The camera
    // may scroll that far past the world's bottom (into the sea), so the lowest
    // ground can always be brought above the dock.
    let dockPad = 0;
    const measureDock = () => {
      const dock = document.getElementById("arena-hud");
      if (!dock || !canvas.getBoundingClientRect) return 0;
      const c = canvas.getBoundingClientRect();
      const d = dock.getBoundingClientRect();
      const over = c.bottom - d.top;
      if (!d.height || over <= 0 || d.top < c.top) return 0;
      return (over + 8) / (c.height / VIEW_H);
    };
    const scale = () => CELL;
    const cam = { x: 0, y: 0 };
    let camReady = false;
    // Free look: the player panned by hand, so the camera stops following for a while.
    let freeLookUntil = 0;
    // Edge scrolling waits for the mouse to move after a cast or a new turn, so a
    // pointer left near the side after a throw doesn't drag the camera away.
    let edgeArmed = false;
    let pointer: { x: number; y: number } | null = null;
    // Lobbed spells charge while the button is held, like a power bar.
    let charge: { start: number; spell: string } | null = null;
    const CHARGE_MS = 1300;
    // The hint under the wizard teaches the charge; after a few throws it is known.
    const THROWS_KEY = "spellslingers_throws";
    const store = globalThis.localStorage as Storage | undefined;
    let throwsSeen = Number(store?.getItem(THROWS_KEY)) || 0;
    // Where each unit is drawn. Steps glide toward the server position; jumps of
    // more than a few cells are teleports and flash at both ends.
    const drawn = new Map<string, [number, number]>();
    let cells: Uint8Array | null = null;
    let ceiling = false;
    const solidAt = (x: number, y: number) =>
      !!shown && !!cells && x >= 0 && x < shown.width && y >= 0 && y < shown.height && cells[y * shown.width + x] === 1;

    // Cells past the world's left and right edges the camera may show, and how far the
    // land is drawn on past them: further than any view reaches, so it never ends on screen.
    const EDGE_VIEW = 14;
    const EDGE_FADE = 22;
    const clampCam = () => {
      if (!shown) return;
      // A little past the left and right edges shows the land carrying on beyond the
      // dashed line, so the world never stops dead at the screen's edge.
      const lo = -EDGE_VIEW;
      const hi = shown.width + EDGE_VIEW - VIEW_W;
      cam.x = hi < lo ? (shown.width - VIEW_W) / 2 : Math.max(lo, Math.min(hi, cam.x));
      // A view taller than the world sits on its bottom, with sky or rock above. The
      // view may also rise a little past the top, so a broom flying at the ceiling
      // keeps its rider and name on screen.
      const maxY = shown.height + dockPad - VIEW_H;
      cam.y = Math.max(Math.min(-8, maxY), Math.min(maxY, cam.y));
    };
    const palette = () => PALETTES[shown?.map_id ?? "isles"] ?? PALETTES.isles;

    // Numbers pop just over the unit; hints start higher (`above` cells), over its
    // name and turn arrow, so they never print on top of them.
    const floatText = (unit: Unit, text: string, color: string, size: number, above = 3) => {
      const s = scale();
      const max = size > 20 ? 1800 : 1300;
      const [x, y] = drawn.get(unit.id) ?? [unit.x, unit.y];
      floaters.push({ x: (x + 0.5) * s, y: (y - above) * s, text, color, size, life: max, max });
    };

    // Shows how much each unit's health changed between two states, where it stood.
    // One sound per kind of change, at the size of the biggest hit, so a quake hitting
    // everyone is one thump rather than a pile of them.
    // Units in `skip` are left to the cast playing, which shows their knockout itself.
    const announceChanges = (before: ArenaState, after: ArenaState, skip?: Set<string>) => {
      const old = new Map(before.units.map((u) => [u.id, u]));
      let worstHit = 0;
      let healed = false;
      let summoned = false;
      for (const unit of after.units) {
        if (skip?.has(unit.id)) continue;
        const prev = old.get(unit.id);
        if (!prev) {
          summoned ||= !unit.dead;
          continue;
        }
        const delta = unit.hp - prev.hp;
        if (unit.dead && !prev.dead) floatText(prev, "KO!", "#dc2626", 30);
        else if (delta < 0) floatText(prev, `${delta}`, "#ef4444", delta <= -30 ? 24 : 18);
        if (delta < 0) hurtAt.set(unit.id, performance.now());
        else if (delta > 0) floatText(prev, `+${delta}`, "#16a34a", 18);
        if (delta < 0) worstHit = Math.max(worstHit, -delta);
        if (delta > 0) healed = true;
      }
      if (worstHit) sounds.hurt(worstHit);
      if (healed) sounds.heal();
      if (summoned) sounds.summoned();
    };

    const show = (state: ArenaState, skip?: Set<string>) => {
      const jump = state.last_jump;
      const newJump = !!shown && !!jump && jump.n !== seenJump;
      // Fall damage shows when the flamingo lands, not as it leaves the top: a jumper,
      // or one still above the spot it drops to (off a ledge, or its ground blasted away).
      if (shown && shown.units !== state.units) {
        const old = new Map(shown.units.map((u) => [u.id, u]));
        for (const after of state.units) {
          const before = old.get(after.id);
          if (!before || before.dead || skip?.has(after.id) || after.hp >= before.hp || (after.float ?? 0) > 0) continue;
          const at = drawn.get(after.id) ?? [before.x, before.y];
          const dropping = falls.has(after.id) || (after.y - at[1] > 2 && Math.abs(after.x - at[0]) <= 2);
          if (!(newJump && jump!.id === after.id) && !dropping) continue;
          fallHurt.set(after.id, (fallHurt.get(after.id) ?? 0) + after.hp - before.hp);
          if (after.dead) fallKO.add(after.id);
          skip = new Set([...(skip ?? []), after.id]);
        }
        announceChanges(shown, state, skip);
      }
      if (jump && jump.n !== seenJump) {
        seenJump = jump.n;
        if (newJump) {
          jumping = { id: jump.id, path: jump.path, start: performance.now() };
          sounds.jump();
        }
      }
      const key = state.terrain + state.map_id;
      // A new turn brings a fresh step budget; within a turn, steps already taken
      // here and not yet confirmed stay spent, and steps the server adds (a broomstick's
      // fuel) are added here too.
      const newTurn = !shown || shown.current_id !== state.current_id || shown.phase !== state.phase;
      const gained = Math.max(0, (state.walk_left ?? 0) - (shown?.walk_left ?? 0));
      stepsLeft = newTurn ? state.walk_left ?? 0 : Math.min(stepsLeft + gained, state.walk_left ?? 0);
      if (newTurn) {
        predicted = null;
        edgeArmed = false;
      }
      // A rematch starts on a fresh island with no casts yet: old scorch marks go.
      if (shown?.last_cast && !state.last_cast) scorches = [];
      // A new duel waits for this page again, and plays its intro again.
      if (state.phase === "arena_loading" && shown?.phase !== "arena_loading") {
        reported = false;
        introAt = null;
        spawned.clear();
      }
      shown = state;
      // Full view shows open sky above the 2:1 map, in the sky's top colour.
      if (sky) sky.style.background = palette().sky[0];
      if (key !== terrainKey) {
        terrainKey = key;
        const next = decodeTerrain(state.terrain, state.width, state.height);
        // The craters a cast carved here already match the server's land: keep the paint.
        const same = !!cells && cells.length === next.length && next.every((v, i) => v === cells![i]);
        cells = next;
        // A world whose top row is mostly rock (the cavern) has a ceiling to continue upward.
        let top = 0;
        for (let x = 0; x < state.width; x++) top += cells[x];
        ceiling = top > state.width / 2;
        if (!same) landDirty = true;
      }
      if (state.last_cast) seenCastId = state.last_cast.id;
      castLocked = false;
      // A charge belongs to the turn it started in.
      if (state.phase !== "arena_aim" || state.current_id !== state.viewer_id) charge = null;
    };

    const receive = (state: ArenaState) => {
      const cast = state.last_cast;

      if (animation) {
        if (cast?.id === animation.cast.id) pending = state;
        else backlog.push(state);
      } else if (shown && cast && cast.id !== seenCastId) {
        seenCastId = cast.id;
        // A grand spell holds its flight back while the title card plays.
        const intro = cast.grand ? shown.physics.grand_intro_ms ?? 1300 : 0;
        const at = performance.now();
        animation = {
          cast,
          start: at + intro,
          landed: new Set(),
          aftermathAt: null,
          hits: [...(cast.hits ?? [])].sort((a, b) => a.at - b.at),
          koShown: new Set(),
          koAt: null,
        };
        if (cast.grand) {
          const def = spellById(cast.spell);
          grand = { start: at, name: def?.name ?? "Grand spell", color: def?.color ?? "#fb923c" };
        }
        pending = state;
        castLocked = true;
        edgeArmed = false;
        sounds.cast(cast, (shown.physics.dt * 1000) / shown.physics.playback_speed);
        // The staff flares as the spell leaves it.
        const caster = shown.units.find((u) => u.id === cast.caster_id);
        if (caster) {
          const s = scale();
          const [cx, cy] = drawn.get(caster.id) ?? [caster.x, caster.y];
          const color = colorOf(cast.spell, "#facc15");
          const [fx, fy] = rigTip(WIZARD.release, anims.get(caster.id)?.wing ?? RIG[WIZARD.release].wing.angle);
          const ox = (cx + 0.5) * s + (faced.get(caster.id) ?? 1) * fx * SHEET_TALL * s;
          const oy = (cy + 1) * s - fy * SHEET_TALL * s;
          burst(ox, oy, color, 22, 110);
          burst(ox, oy, "#fff", 10, 70);
          rings.push({ x: ox, y: oy, r: 22, born: at + intro, color });
        }
      } else {
        show(state);
      }
    };

    // ---- Physics mirror, used only for the aiming preview ----
    const spellById = (id: string) => shown?.spells.find((s) => s.id === id);
    const spellDef = () => spellById(selected);
    const colorOf = (id: string, fallback: string) => (id === "surge" ? SURGE_COLOR : spellById(id)?.color ?? fallback);
    const isBeam = (id: string) => spellById(id)?.input === "beam";

    const myWizard = () => shown?.units.find((u) => u.kind === "wizard" && u.id === shown?.viewer_id && !u.dead);

    const canAct = () =>
      !!shown &&
      lifted &&
      shown.phase === "arena_aim" &&
      shown.current_id === shown.viewer_id &&
      !animation &&
      !castLocked &&
      !jumping &&
      !!myWizard();
    // During the retreat after a cast the wizard still moves, but casts nothing more.
    const canCast = () => canAct() && !shown!.retreat;

    // The server's flight step: wind and gravity change the velocity, then it moves.
    const previewPath = (power: number, steps: number) => {
      const wizard = myWizard();
      const spell = spellDef();
      if (!shown || !wizard || !spell || !aim || spell.input === "instant") return [];
      const p = shown.physics;
      const speed = (p.max_speed * spell.speed * Math.max(power, 5)) / 100;
      const rad = (aim.angle * Math.PI) / 180;
      const ax = shown.wind * p.wind_accel * spell.wind;
      const ay = p.gravity * spell.gravity;
      let vx = Math.cos(rad) * speed;
      let vy = -Math.sin(rad) * speed;
      let x = wizard.x + 0.5;
      let y = wizard.y - 2;
      const points: [number, number][] = [];
      for (let i = 0; i < steps; i++) {
        vx += ax * p.dt;
        vy += ay * p.dt;
        x += vx * p.dt;
        y += vy * p.dt;
        if (x < 0 || x >= shown.width || y >= shown.water_level || solidAt(Math.floor(x), Math.floor(y))) break;
        points.push([x, y]);
      }
      return points;
    };

    // ---- Drawing ----
    const drawBackground = (t: number) => {
      const pal = palette();
      const backdrop = art.backdrops[shown?.map_id ?? ""];
      if (shown && ready(backdrop)) {
        // The painting is a far layer: it slides a tenth as far as the world when the
        // camera pans and grows a little when it zooms, both around the view's middle,
        // so the distance reads as distance. It is sized so it never runs out, even
        // zoomed all the way in at the edge of the world.
        const DEPTH = 0.1;
        const grow = (zoom / ZOOM_MIN) ** 0.2;
        const k = Math.max(W / backdrop.naturalWidth, H / backdrop.naturalHeight) * 1.08 * grow;
        const bw = backdrop.naturalWidth * k;
        const bh = backdrop.naturalHeight * k;
        const slideX = (cam.x + VIEW_W / 2 - shown.width / 2) * CELL * zoom * DEPTH;
        const slideY = (cam.y + VIEW_H / 2 - shown.height / 2) * CELL * zoom * DEPTH;
        const x = Math.max(W - bw, Math.min(0, (W - bw) / 2 - slideX));
        const y = Math.max(H - bh, Math.min(0, (H - bh) / 2 - slideY));
        ctx.drawImage(backdrop, x, y, bw, bh);
        if (shown.map_id === "cavern") {
          for (let i = 0; i < 40; i++) {
            ctx.globalAlpha = 0.3 + 0.3 * Math.sin(t / 700 + i);
            ctx.fillStyle = i % 3 === 0 ? "#67e8f9" : "#c4b5fd";
            ctx.fillRect((i * 137) % W, (i * 89) % H, 2, 2);
          }
          ctx.globalAlpha = 1;
        }
        return;
      }
      const sky = ctx.createLinearGradient(0, 0, 0, H);
      sky.addColorStop(0, pal.sky[0]);
      sky.addColorStop(0.7, pal.sky[1]);
      sky.addColorStop(1, pal.sky[2]);
      ctx.fillStyle = sky;
      ctx.fillRect(0, 0, W, H);

      const cavern = shown?.map_id === "cavern";

      if (cavern) {
        for (let i = 0; i < 40; i++) {
          ctx.globalAlpha = 0.3 + 0.3 * Math.sin(t / 700 + i);
          ctx.fillStyle = i % 3 === 0 ? "#67e8f9" : "#c4b5fd";
          ctx.fillRect((i * 137) % W, (i * 89) % H, 2, 2);
        }
        ctx.globalAlpha = 1;
      } else {
        ctx.fillStyle = shown?.map_id === "castles" ? "rgba(254, 240, 138, 0.9)" : "rgba(255, 237, 213, 0.9)";
        ctx.beginPath();
        ctx.arc(W * 0.82, H * (shown?.map_id === "castles" ? 0.42 : 0.18), 34, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.fillStyle = pal.hills;
      ctx.beginPath();
      ctx.moveTo(0, H - 190);
      for (let x = 0; x <= W; x += 40) ctx.lineTo(x, H - 250 + Math.sin(x * 0.011) * 40 + Math.sin(x * 0.031) * 14);
      ctx.lineTo(W, H);
      ctx.lineTo(0, H);
      ctx.fill();

      if (cavern) return;
      const wind = shown?.wind ?? 0;
      ctx.fillStyle = "rgba(255,255,255,0.8)";
      for (let i = 0; i < 5; i++) {
        const drift = (t / 1000) * (6 + wind * 6);
        const x = ((((i * 233 + drift) % (W + 200)) + W + 200) % (W + 200)) - 100;
        const y = 40 + ((i * 71) % 110);
        for (const [dx, dy, r] of [[0, 0, 18], [18, -8, 22], [40, 0, 16]]) {
          ctx.beginPath();
          ctx.arc(x + dx, y + dy, r, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    };

    // Dashed lines mark how far a wizard can walk. Only a knock carries anyone past
    // them, and then nothing stops the fall until the sea.
    const drawEdgeLines = () => {
      if (!shown) return;
      const top = (cam.y - 2) * CELL;
      const bottom = shown.water_level * CELL;
      ctx.save();
      ctx.lineCap = "round";
      for (const x of [0, shown.width * CELL]) {
        // The same width and dashes on screen at any zoom.
        for (const [color, width] of [["rgba(28,25,23,0.45)", 8], ["rgba(255,255,255,0.9)", 4]] as const) {
          ctx.setLineDash([18 / zoom, 14 / zoom]);
          ctx.lineDashOffset = -top;
          ctx.strokeStyle = color;
          ctx.lineWidth = width / zoom;
          ctx.beginPath();
          ctx.moveTo(x, top);
          ctx.lineTo(x, bottom);
          ctx.stroke();
        }
      }
      ctx.restore();
    };

    const drawWater = (t: number) => {
      if (!shown) return;
      const s = scale();
      const top = shown.water_level * s;
      ctx.fillStyle = palette().water;
      ctx.beginPath();
      const worldW = shown.width * s;
      const x0 = -EDGE_FADE * s;
      const x1 = worldW + EDGE_FADE * s;
      const bottom = (shown.height + dockPad + 4) * s;
      ctx.moveTo(x0, bottom);
      for (let x = x0; x <= x1; x += 10) ctx.lineTo(x, top + Math.sin(x * 0.04 + t / 400) * 3);
      ctx.lineTo(x1, bottom);
      ctx.fill();
      // Deeper down the sea turns opaque, so rock under it and open water read as one
      // sea instead of lighter and darker blocks with hard seams between them.
      const deep = ctx.createLinearGradient(0, top + 0.5 * s, 0, top + 4 * s);
      deep.addColorStop(0, "rgba(0,0,0,0)");
      deep.addColorStop(1, palette().water.replace(/[\d.]+\)$/, "1)"));
      ctx.fillStyle = deep;
      ctx.fillRect(x0, top + 0.5 * s, x1 - x0, bottom - top);
      // A lighter band of rolling swell just under the surface.
      ctx.fillStyle = "rgba(255,255,255,0.13)";
      ctx.beginPath();
      for (let x = x0; x <= x1; x += 10) ctx.lineTo(x, top + 2 * s + Math.sin(x * 0.025 - t / 650) * 3);
      for (let x = x1; x >= x0; x -= 10) ctx.lineTo(x, top + 3.2 * s + Math.sin(x * 0.03 - t / 500) * 3);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.85)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      for (let x = x0; x <= x1; x += 10) ctx.lineTo(x, top + Math.sin(x * 0.04 + t / 400) * 3);
      ctx.stroke();
    };

    // A flamingo's pose comes from what it is doing; the sheet is painted facing right.
    type Pose = "idle" | "crouch" | "walk" | "aim" | "cast" | "jump" | "drop" | "land" | "hurt" | "tumble" | "win" | "fly" | "spawn" | "greet";
    // How tall the sheet's cell is drawn, in cells; a standing flamingo fills about 0.9 of
    // it. Nameplates sit LABEL_TALL cells above the feet, just over the head tuft.
    const SHEET_TALL = 8.8;
    const LABEL_TALL = 8.6;
    // How far each flamingo has walked, which drives its stride so the feet never skate.
    const walked = new Map<string, number>();
    const faced = new Map<string, number>();
    const landedAt = new Map<string, number>();
    // Each dropping flamingo: how fast it falls, in cells per ms, and when it went over.
    const falls = new Map<string, { v: number; at: number }>();
    // A flamingo drops slower than a spell flies: its wings catch the air. It falls at
    // under half the spells' gravity up to a top speed, and every FLAP_EVERY ms it beats
    // its wings for FLAP_MS, braking. A 30-cell ledge takes about 1.4 s, over twice as long.
    const FALL_GRAVITY = 0.55;
    const FALL_TOP = 0.034;
    const FLAP_FIRST = 300;
    const FLAP_EVERY = 600;
    const FLAP_MS = 170;
    const flapping = (since: number) => since > FLAP_FIRST && (since - FLAP_FIRST) % FLAP_EVERY < FLAP_MS;
    // When each flamingo last moved along the ground, so a pause between steps isn't a stop.
    const movedAt = new Map<string, number>();
    // The last frame's length, for the springs below.
    let frameDt = 16;
    // Each flamingo's animation: its pose and since when, a squash-and-stretch spring (sq
    // above 0 stretches it tall, below 0 squashes it wide), an eased tilt, and the frame it
    // showed last, which fades out over the new one so poses blend instead of snapping.
    // A rigged frame (see RIG) is drawn into `shot` with its wing and head eased toward
    // the aim, and `from` keeps the last one to fade out. `face` eases between -1 and 1
    // so turning around swings the flamingo through edge-on instead of flipping it.
    type Anim = {
      pose: Pose;
      since: number;
      sq: number;
      v: number;
      tilt: number;
      frame: number;
      prev: number;
      swapAt: number;
      wing: number;
      head: number;
      face: number;
      shot: HTMLCanvasElement | null;
      from: HTMLCanvasElement | null;
    };
    const anims = new Map<string, Anim>();
    const animOf = (id: string, t: number) => {
      let a = anims.get(id);
      // Long since settled, so a flamingo first seen standing doesn't shift its feet.
      if (!a) anims.set(id, (a = { pose: "idle", since: -1e9, sq: 0, v: 0, tilt: 0, frame: WIZARD.idle, prev: WIZARD.idle, swapAt: -1e9, wing: 0, head: 0, face: 0, shot: null, from: null }));
      return a;
    };
    // The kick each pose gives the spring as it starts: a stretch on take-off and on a
    // throw, a squash on landing and on being hit. It rings out with a little overshoot.
    const POP: Partial<Record<Pose, number>> = { jump: 2.6, land: -3.6, hurt: -2.4, cast: 2, crouch: -1.6, aim: 0.7, walk: 0.5, idle: -0.6, fly: 1.6, win: 1.6, tumble: 1.2, spawn: 1.4, greet: 0.8 };
    const BLEND_MS = 90;
    // The way a flamingo is aiming, in degrees above its facing (negative is down).
    const aimLift = (unit: Unit, facing: number) => {
      let deg: number | null = null;
      if (unit.id === shown?.viewer_id && aim) deg = aim.angle;
      else if (unit.id === shown?.current_id && shown?.bot_aim) {
        const a = shown.bot_aim;
        deg = a.x !== undefined && a.y !== undefined ? (Math.atan2(unit.y - 2 - a.y, a.x - unit.x) * 180) / Math.PI : (a.angle ?? 0);
      }
      if (deg === null) return 0;
      const lift = facing > 0 ? deg : 180 - deg;
      return ((lift + 540) % 360) - 180;
    };
    const drawWizard = (unit: Unit, t: number, facing: number, pose: Pose) => {
      if (!shown) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const feet = (unit.y + 1) * s;
      const color = shown.players[unit.id]?.color ?? "#9ca3af";

      if (unit.dead) {
        // A gravestone where the flamingo fell.
        ctx.lineWidth = 2;
        ctx.strokeStyle = "#111827";
        ctx.fillStyle = "#a8a29e";
        ctx.beginPath();
        ctx.roundRect(cx - 8, feet - 20, 16, 20, [8, 8, 1, 1]);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = "#57534e";
        ctx.fillRect(cx - 1.2, feet - 16, 2.4, 10);
        ctx.fillRect(cx - 4.5, feet - 13, 9, 2.4);
        ctx.fillStyle = color;
        ctx.fillRect(cx - 8, feet - 3, 16, 3);
        return;
      }

      const img = art.wizard;
      if (!ready(img)) return;
      const sheet = wizardSheet(img, color);
      const h = SHEET_TALL * s;
      const w = (h * WIZARD_W) / WIZARD_H;
      const a = animOf(unit.id, t);
      if (a.pose !== pose) {
        a.v += POP[pose] ?? 0;
        a.pose = pose;
        a.since = t;
      }
      const since = t - a.since;
      let frameAt: number = WIZARD.idle;
      // Squash added on top of the spring, a lift off the ground, a spin, and a shake.
      let squash = 0;
      let lift = 0;
      let spin = 0;
      let jitter = 0;
      let tilt = 0;
      // Where a rigged frame's wing and head turn to, in degrees above level.
      let wingTo = 0;
      let headTo = 0;
      // Each flamingo keeps its own rhythm, so a flock doesn't blink in step.
      const own = (unit.x * 0.37 + unit.id.length * 1.3) * 1000;
      const phase = (t + own) / 1000;
      switch (pose) {
        case "idle": {
          // Settles from both feet onto one, breathes, blinks, and now and then preens
          // or glances over its shoulder.
          squash = Math.sin(phase * 2.4) * 0.016;
          const blink = (t + own) % 3900;
          const preen = (t + own * 3) % 12000;
          const glance = (t + own * 7) % 9000;
          if (since < 260) frameAt = WIZARD.stand;
          else if (preen < 1500) frameAt = WIZARD.preen;
          else if (glance < 900) frameAt = WIZARD.glance;
          else if (blink < 140) frameAt = WIZARD.blink;
          break;
        }
        case "crouch":
          frameAt = WIZARD.crouch;
          squash = -0.05;
          break;
        case "walk":
          frameAt = WIZARD.walk + (Math.floor((walked.get(unit.id) ?? 0) / 0.7) % 8);
          // Leans into the strut.
          tilt = 0.05;
          break;
        case "aim": {
          // The wing points along the aim and the head half follows it.
          const up = Math.max(-75, Math.min(88, aimLift(unit, facing)));
          frameAt = WIZARD.aim;
          wingTo = up;
          headTo = Math.max(-14, Math.min(20, up * 0.3));
          squash = Math.sin(phase * 3) * 0.01;
          if (charge && unit.id === shown.viewer_id) {
            // Rears back, cocking the wing over its shoulder, and trembles more the
            // harder it charges.
            const power = chargePower(t) / 100;
            wingTo = Math.min(130, up + power * 45);
            headTo -= power * 6;
            squash = -power * 0.06;
            jitter = Math.sin(t / 24) * power * 1.3;
            tilt = -power * 0.06;
          }
          break;
        }
        case "cast": {
          // Flings the wing, then overbalances after it.
          // The wing whips through to the way the spell left.
          const el = animation ? t - animation.start : 0;
          frameAt = el < 170 ? WIZARD.release : WIZARD.follow;
          const path = animation?.cast.segments[0]?.path;
          const k = path ? Math.min(3, path.length - 1) : 0;
          wingTo = path && k > 0 ? Math.max(-75, Math.min(88, (Math.atan2(path[0][1] - path[k][1], Math.abs(path[k][0] - path[0][0])) * 180) / Math.PI)) : a.wing;
          headTo = Math.max(-14, Math.min(20, wingTo * 0.3));
          tilt = el < 170 ? 0.04 : 0.07;
          break;
        }
        case "jump": {
          frameAt = WIZARD.rise;
          if (jumping?.id === unit.id) {
            const p = shown.physics;
            const path = jumping.path;
            const step = ((t - jumping.start) / 1000) * (p.playback_speed / p.dt);
            const i = Math.max(0, Math.min(path.length - 2, Math.floor(step)));
            const vx = path[i + 1][0] - path[i][0];
            const vy = path[i + 1][1] - path[i][1];
            let top = path[0][1];
            for (const q of path) top = Math.min(top, q[1]);
            // A long jump is low and far: the flamingo flutters across it.
            const long = Math.abs(path[path.length - 1][0] - path[0][0]) > (path[0][1] - top) * 2.2;
            const left = path.length - 1 - step;
            if (step < 1.2) frameAt = WIZARD.crouch;
            else if (left < 2.5 && vy > 0) frameAt = WIZARD.fall;
            else if (long) {
              const flap = Math.floor((t - jumping.start) / 85) % 2;
              frameAt = flap ? WIZARD.flapDown : WIZARD.flapUp;
              squash = flap ? -0.03 : 0.03;
              if (frame % 9 === 0) burst(cx - facing * 12, feet - h * 0.45, "#f9a8d4", 1, 18);
            } else frameAt = vy < -0.15 ? WIZARD.rise : vy > 0.15 ? WIZARD.fall : WIZARD.flapDown;
            // Noses up on the way up and down on the way down.
            tilt = Math.atan2(vy, Math.max(0.3, Math.abs(vx))) * 0.3;
          }
          break;
        }
        case "fly": {
          // Taking flight: wings beat steadily, feathers drift off behind.
          frameAt = Math.floor((t + own) / 115) % 2 ? WIZARD.flapDown : WIZARD.flapUp;
          squash = frameAt === WIZARD.flapDown ? -0.03 : 0.03;
          lift = frameAt === WIZARD.flapDown ? 1.5 : 0;
          if (frame % 12 === 0) burst(cx - facing * 14, feet - h * 0.4, "#f9a8d4", 1, 16);
          break;
        }
        case "drop": {
          // Legs dangling on the way down, with the odd beat of the wings to slow it.
          const since = t - (falls.get(unit.id)?.at ?? t);
          if (flapping(since)) {
            const flap = Math.floor((since - FLAP_FIRST) / 90) % 2;
            frameAt = flap ? WIZARD.flapUp : WIZARD.flapDown;
            squash = flap ? 0.03 : -0.03;
            if (frame % 6 === 0) burst(cx - facing * 12, feet - h * 0.45, "#f9a8d4", 1, 18);
          } else {
            frameAt = WIZARD.fall;
            squash = 0.06;
          }
          break;
        }
        case "land":
          frameAt = WIZARD.land;
          break;
        case "spawn":
          // Dropping into the arena, stretched by the fall.
          frameAt = WIZARD.fall;
          squash = 0.08;
          break;
        case "greet":
          // Looks out at everyone, then turns to the duel.
          frameAt = t - (spawnAt(unit.id) ?? t) < SPAWN_DROP_MS + 820 ? WIZARD.front : WIZARD.recover;
          break;
        case "hurt": {
          const el = t - (hurtAt.get(unit.id) ?? t);
          if (el < 320) {
            frameAt = WIZARD.hurt;
            jitter = Math.sin(t / 22) * 2.2 * (1 - el / 320);
          } else {
            frameAt = WIZARD.dizzy;
            tilt = Math.sin(t / 110) * 0.12;
          }
          break;
        }
        case "tumble":
          // Curled into a ball and rolling the way it was thrown.
          frameAt = WIZARD.tumble;
          spin = (t / 90) * facing;
          break;
        case "win": {
          const beat = (t + own) / 380;
          frameAt = Math.floor(beat) % 2 ? WIZARD.cheer : WIZARD.dance;
          const hop = Math.abs(Math.sin(beat * Math.PI));
          lift = hop * 5;
          squash = (hop - 0.5) * 0.08;
          break;
        }
      }

      // The spring, stepped by this frame's time.
      const dt = Math.min(frameDt, 40) / 1000;
      a.v += (-340 * a.sq - 15 * a.v) * dt;
      a.sq += a.v * dt;
      a.tilt += (tilt - a.tilt) * (1 - Math.exp(-frameDt / 90));
      const rigged = !!RIG[frameAt];
      if (frameAt !== a.frame) {
        // Walk frames follow each other; anything else blends from the frame before.
        if (frameAt >= WIZARD.idle || a.frame >= WIZARD.idle) {
          a.prev = a.frame;
          a.swapAt = t;
          if (RIG[a.prev] && a.shot) {
            a.from ??= document.createElement("canvas");
            a.from.width = WIZARD_W;
            a.from.height = WIZARD_H;
            a.from.getContext("2d")!.drawImage(a.shot, 0, 0);
          }
        }
        // Coming from an unrigged frame, the wing starts where it is painted.
        if (rigged && !RIG[a.frame]) {
          a.wing = RIG[frameAt].wing.angle;
          a.head = 0;
        }
        a.frame = frameAt;
      }
      // Quick enough to keep up with the pointer, slow enough to smooth its jitter.
      const ease = 1 - Math.exp(-frameDt / 45);
      a.wing += (wingTo - a.wing) * ease;
      a.head += (headTo - a.head) * ease;
      // Turning gives a little hop of the spring, and edge-on is never quite flat.
      if (!a.face) a.face = facing;
      if (Math.abs(a.face) === 1 && a.face !== facing) a.v += 0.6;
      a.face += Math.max(-frameDt / 65, Math.min(frameDt / 65, facing - a.face));
      const turnX = Math.sign(a.face || facing) * Math.max(0.3, Math.abs(a.face));
      const sq = Math.max(-0.3, Math.min(0.3, a.sq + squash));
      const sy = 1 + sq;
      const sx = 1 - sq * 0.55;

      // A soft shadow on the ground, smaller as the flamingo leaves it.
      if (pose !== "jump" && pose !== "tumble" && pose !== "fly" && pose !== "spawn") {
        ctx.fillStyle = "rgba(0,0,0,0.22)";
        ctx.beginPath();
        ctx.ellipse(cx, feet, Math.max(2, h * 0.16 * sx - lift * 0.4), 2, 0, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.save();
      ctx.translate(cx + jitter, feet - lift);
      if (spin) {
        // The ball sits low in its cell; it rolls about its own middle.
        ctx.translate(0, -h * 0.25);
        ctx.rotate(spin);
        ctx.translate(0, h * 0.25);
      } else if (a.tilt) {
        ctx.translate(0, -h * 0.4);
        ctx.rotate(a.tilt * facing);
        ctx.translate(0, h * 0.4);
      }
      ctx.scale(turnX * sx, sy);
      if (rigged) {
        a.shot ??= Object.assign(document.createElement("canvas"), { width: WIZARD_W, height: WIZARD_H });
        ctx.drawImage(poseRig(a.shot, sheet, frameAt, a.wing, a.head), -w / 2, -h, w, h);
      } else ctx.drawImage(sheet, frameAt * WIZARD_W, 0, WIZARD_W, WIZARD_H, -w / 2, -h, w, h);
      const blend = (t - a.swapAt) / BLEND_MS;
      if (blend < 1 && a.prev !== frameAt) {
        ctx.globalAlpha = 1 - blend;
        if (RIG[a.prev] && a.from) ctx.drawImage(a.from, -w / 2, -h, w, h);
        else ctx.drawImage(sheet, a.prev * WIZARD_W, 0, WIZARD_W, WIZARD_H, -w / 2, -h, w, h);
        ctx.globalAlpha = 1;
      }
      ctx.restore();

      // The wing tip swells with light while a throw charges.
      if (pose === "aim" && charge && unit.id === shown.viewer_id) {
        const power = chargePower(t) / 100;
        const [fx, fy] = rigged ? rigTip(frameAt, a.wing) : (WINGTIP[frameAt] ?? WINGTIP[WIZARD.aim]);
        const ox = cx + jitter + turnX * fx * h * sx;
        const oy = feet - fy * h * sy;
        const r = 4 + power * 10 + Math.sin(t / 60) * 1.2;
        const glow = ctx.createRadialGradient(ox, oy, 0, ox, oy, r);
        const tint = colorOf(charge.spell, "#facc15");
        glow.addColorStop(0, "rgba(255,255,255,0.95)");
        glow.addColorStop(0.35, tint);
        glow.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(ox, oy, r, 0, Math.PI * 2);
        ctx.fill();
        if (frame % 4 === 0) burst(ox, oy, tint, 1, 14 + power * 30);
      }
    };

    const drawCrate = (crate: Crate, t: number) => {
      const img = art.crates;
      if (!ready(img)) return;
      const s = scale();
      const cx = (crate.x + 0.5) * s;
      const feet = (crate.y + 1) * s;
      const size = 13;
      const glow = 0.5 + 0.5 * Math.sin(t / 250 + crate.x);
      ctx.globalAlpha = 0.25 + glow * 0.25;
      ctx.fillStyle = crate.type === "health" ? "#fecaca" : "#bfdbfe";
      ctx.beginPath();
      ctx.arc(cx, feet - size / 2, size * 0.75, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
      ctx.drawImage(img, CRATE_FRAME[crate.type] * CRATE_SIZE, 0, CRATE_SIZE, CRATE_SIZE, cx - size / 2, feet - size, size, size);
    };

    // A spell's painted sprite, centred on (x, y), `size` across, turned by `angle`.
    const sprite = (id: string, x: number, y: number, size: number, angle = 0, flip = 1) => {
      const img = art.spells;
      const n = spellById(id)?.sprite;
      if (!ready(img) || n === undefined) return false;
      ctx.save();
      ctx.translate(x, y);
      ctx.scale(flip, 1);
      ctx.rotate(angle);
      ctx.drawImage(img, n * SPELL_CELL, 0, SPELL_CELL, SPELL_CELL, -size / 2, -size / 2, size, size);
      ctx.restore();
      return true;
    };

    // The shrimp's fishing line from (x0, y0) to (x1, y1), sagging a little.
    const chain = (x0: number, y0: number, x1: number, y1: number) => {
      const sag = Math.min(16, Math.hypot(x1 - x0, y1 - y0) * 0.08);
      ctx.strokeStyle = "rgba(255,255,255,0.9)";
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.quadraticCurveTo((x0 + x1) / 2, (y0 + y1) / 2 + sag, x1, y1);
      ctx.stroke();
    };

    // Nest Eggs fizz where they rolled to until the turn ends, then go off. The egg rolls
    // on the server as a circle of radius eggR() cells; the sprite's egg is about 0.73 of
    // its cell wide, so this size makes the drawn egg a little wider than that circle.
    const eggR = () => shown?.physics.egg_radius ?? 1;
    const eggSize = () => (eggR() * 2.1 * scale()) / 0.73;
    const drawEgg = (x: number, y: number, spin: number, size: number) => {
      sprite("blastrune", x, y, size, spin);
      // Sparks fly from the fuse at the top of its crack, wherever that has rolled to.
      const [fx, fy] = [0.3 * size, -0.34 * size];
      if (frame % 3 === 0) burst(x + fx * Math.cos(spin) - fy * Math.sin(spin), y + fx * Math.sin(spin) + fy * Math.cos(spin), "#fde047", 1, 25);
    };
    const drawRunes = (t: number) => {
      if (!shown) return;
      const s = scale();
      for (const rune of shown.runes ?? []) {
        const x = rune.x * s;
        const y = rune.y * s;
        const pulse = 0.5 + 0.5 * Math.sin(t / 90);
        const glow = ctx.createRadialGradient(x, y, 2, x, y, 26);
        glow.addColorStop(0, `rgba(217, 70, 239, ${0.35 + pulse * 0.35})`);
        glow.addColorStop(1, "rgba(217, 70, 239, 0)");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(x, y, 26, 0, Math.PI * 2);
        ctx.fill();
        drawEgg(x, y, rune.spin ?? 0, eggSize() * (1 + pulse * 0.06));
      }
    };

    // Glowing rims the biggest blasts leave behind, cooling over a few seconds.
    const drawScars = (t: number) => {
      const s = scale();
      for (const scar of scars) {
        const k = 1 - (t - scar.born) / 5000;
        if (k <= 0) continue;
        ctx.strokeStyle = `rgba(251, 146, 60, ${k * 0.9})`;
        ctx.lineWidth = 3 + 3 * k;
        ctx.beginPath();
        ctx.arc(scar.x * s, scar.y * s, scar.r * s, 0, Math.PI * 2);
        ctx.stroke();
        if (frame % 3 === 0 && Math.random() < k) {
          const a = Math.random() * Math.PI * 2;
          burst((scar.x + Math.cos(a) * scar.r) * s, (scar.y + Math.sin(a) * scar.r) * s, "#fb923c", 1, 20);
        }
      }
      scars = scars.filter((scar) => t - scar.born < 5000);
    };

    // How far a flying wizard leans, eased: forward into sideways flight, nose up when
    // climbing and down when diving. Velocity is in cells per millisecond.
    const velocity = new Map<string, [number, number]>();
    const leans = new Map<string, number>();
    const leanOf = (id: string, face: number, dt: number) => {
      const [vx, vy] = velocity.get(id) ?? [0, 0];
      const full = 1 / FLY_MS;
      const clamp = (v: number) => Math.max(-1, Math.min(1, v / full));
      const want = clamp(vx) * 0.16 + clamp(vy) * face * 0.14;
      const lean = (leans.get(id) ?? 0) + (want - (leans.get(id) ?? 0)) * (1 - Math.exp(-dt / 120));
      leans.set(id, lean);
      return lean;
    };

    const drawFloaters = (dt: number) => {
      floaters = floaters.filter((f) => (f.life -= dt) > 0);
      ctx.textAlign = "center";
      for (const f of floaters) {
        const k = 1 - f.life / f.max;
        const pop = k < 0.12 ? 0.6 + (k / 0.12) * 0.6 : 1.2 - Math.min(0.2, (k - 0.12) * 0.5);
        ctx.globalAlpha = Math.min(1, (f.life / f.max) * 2.5);
        ctx.font = `900 ${Math.round(f.size * pop)}px ui-sans-serif, system-ui`;
        const y = f.y - k * 34;
        ctx.lineWidth = 4;
        ctx.strokeStyle = "#111827";
        ctx.strokeText(f.text, f.x, y);
        ctx.fillStyle = f.color;
        ctx.fillText(f.text, f.x, y);
      }
      ctx.globalAlpha = 1;
    };

    const drawLabels = (unit: Unit) => {
      if (!shown || unit.dead) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const tall = LABEL_TALL * s + 3;
      const top = (unit.y + 1) * s - tall;

      // In the intro each name is called out big as its flamingo lands instead.
      if (shown.phase !== "arena_intro") {
        const label = shown.players[unit.id]?.name ?? "?";
        ctx.font = "bold 11px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "white";
        ctx.strokeText(label, cx, top - 6);
        ctx.fillStyle = shown.players[unit.id]?.color ?? "#111827";
        ctx.fillText(label, cx, top - 6);
      }

      const w = 26;
      // Fall damage still to show leaves the bar full until the flamingo lands.
      const hp = unit.hp - (fallHurt.get(unit.id) ?? 0);
      const ratio = hp / unit.max_hp;
      const now = performance.now();
      let bar = bars.get(unit.id);
      if (!bar || hp >= bar.v) bars.set(unit.id, (bar = { v: hp, since: now }));
      else if (now - bar.since > 380) bar.v = Math.max(hp, bar.v - (unit.max_hp * 0.6 * 16) / 1000);
      ctx.fillStyle = "#111827";
      ctx.fillRect(cx - w / 2 - 1, top - 2, w + 2, 5);
      ctx.fillStyle = "#fde68a";
      ctx.fillRect(cx - w / 2, top - 1, (w * bar.v) / unit.max_hp, 3);
      ctx.fillStyle = ratio > 0.5 ? "#22c55e" : ratio > 0.25 ? "#f59e0b" : "#ef4444";
      ctx.fillRect(cx - w / 2, top - 1, w * ratio, 3);
    };

    // Where a placed spell would land: open air above the pointer, within range.
    const placeTarget = () => {
      const wizard = myWizard();
      if (!shown || !wizard || !pointer) return null;
      let x = pointer.x / (CELL * zoom) + cam.x;
      let y = pointer.y / (CELL * zoom) + cam.y;
      x = Math.max(0, Math.min(shown.width - 1, x));
      while (y > 1 && solidAt(Math.floor(x), Math.floor(y))) y -= 1;
      const def = spellDef();
      const inRange = !!def?.sky || Math.hypot(x - wizard.x - 0.5, y - wizard.y + 1) <= shown.physics.place_range;
      // A blink lands you on the ground below the spot, so over the sea it drowns you.
      const sinks = def?.effect === "blink" && dropTo(x, y) >= shown.water_level - 1;
      return { x, y, inRange, sinks };
    };

    // Where a wizard would come to rest: straight down onto the ground.
    const dropTo = (x: number, y: number) => {
      if (!shown) return y;
      let yy = y;
      while (yy < shown.water_level && !solidAt(Math.floor(x), Math.floor(yy + 1))) yy += 1;
      return yy;
    };

    const drawAim = (t: number) => {
      const wizard = myWizard();
      const spell = spellDef();
      if (!shown || !wizard || !aim || !canCast() || !spell || spell.input === "instant") return;
      const s = scale();
      const color = spell.color;
      const ox = (wizard.x + 0.5) * s;
      const oy = (wizard.y - 2) * s;

      if (spell.input === "place") {
        const target = placeTarget();
        if (!target) return;
        const ok = target.inRange && !target.sinks;
        ctx.save();
        ctx.setLineDash([6, 6]);
        ctx.lineDashOffset = -t / 40;
        ctx.strokeStyle = "rgba(17,24,39,0.35)";
        ctx.lineWidth = 2;
        if (!spell.sky) {
          ctx.beginPath();
          ctx.arc(ox, (wizard.y - 1) * s, shown.physics.place_range * s, 0, Math.PI * 2);
          ctx.stroke();
        }
        ctx.setLineDash([]);
        const tint = ok ? color : "#ef4444";
        ctx.globalAlpha = 0.55 + 0.15 * Math.sin(t / 160);
        ctx.fillStyle = tint;
        ctx.strokeStyle = "#111827";
        const px = target.x * s;
        const py = target.y * s;
        if (spell.effect === "slab") {
          // The slab as it will hang: a rounded rock ledge like the painted platforms.
          ctx.fillStyle = ok ? "#d6a27a" : tint;
          ctx.lineWidth = Math.max(2, 0.35 * s);
          ctx.beginPath();
          ctx.roundRect(px - 7.5 * s, py - 0.6 * s, 15 * s, 2.2 * s, 1.1 * s);
          ctx.fill();
          ctx.stroke();
        } else if (spell.effect === "meteors") {
          // Five meteors drop straight down these columns: show each streak and the
          // blast ring where it first meets ground.
          for (const [i, dx] of [-12, -6, 0, 6, 12].entries()) {
            const mx = (Math.max(2, Math.min(shown.width - 3, target.x)) + dx + 0.5) * s;
            const land = dropTo(mx / s, 0) * s;
            ctx.globalAlpha = 0.35;
            ctx.setLineDash([4, 6]);
            ctx.lineDashOffset = t / 25;
            ctx.beginPath();
            ctx.moveTo(mx, 0);
            ctx.lineTo(mx, land);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.globalAlpha = 0.3 + 0.12 * Math.sin(t / 160 + i);
            ctx.beginPath();
            ctx.arc(mx, land, (spell.radius ?? 6) * s, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 0.4;
            ctx.stroke();
          }
          ctx.globalAlpha = 1;
          sprite("meteors", px, py, 7 * s, Math.PI / 6);
        } else if (spell.effect === "anvil") {
          ctx.fillRect(px - 4 * s, 0, 8 * s, py);
          ctx.globalAlpha = 1;
          sprite("anvil", px, py - 4 * s, 9 * s);
        } else if (spell.effect === "blink") {
          // A ghost of the wizard where it will land.
          const rest = dropTo(target.x, target.y);
          ctx.setLineDash([3, 4]);
          ctx.beginPath();
          ctx.moveTo(px, py);
          ctx.lineTo(px, rest * s);
          ctx.stroke();
          ctx.setLineDash([]);
          ctx.beginPath();
          ctx.ellipse(px, (rest + 1) * s - 3.8 * s, 2.2 * s, 3.8 * s, 0, 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
          ctx.globalAlpha = 1;
          sprite("blink", px, (rest - 2.8) * s, 8 * s, t / 300);
        }
        ctx.restore();
        if (!ok) {
          ctx.font = "bold 12px ui-sans-serif, system-ui";
          ctx.textAlign = "center";
          ctx.fillStyle = "#b91c1c";
          ctx.fillText(target.inRange ? "Falls in the sea" : "Too far", px, py - 12);
        }
        return;
      }

      const rad = (aim.angle * Math.PI) / 180;
      const dir = [Math.cos(rad), -Math.sin(rad)];

      if (spell.input === "beam") {
        // Beams fly straight, so a straight dashed sight line is honest.
        ctx.save();
        ctx.setLineDash([8, 6]);
        ctx.lineDashOffset = -t / 30;
        ctx.strokeStyle = color;
        ctx.lineWidth = 3;
        ctx.globalAlpha = 0.8;
        ctx.beginPath();
        ctx.moveTo(ox, oy);
        const reach = Math.min(spell.range ?? 45, 45);
        ctx.lineTo(ox + dir[0] * reach * s, oy + dir[1] * reach * s);
        ctx.stroke();
        ctx.restore();
      } else {
        // The start of the real arc, wind included: longer while charging, never the landing spot.
        const power = charge ? chargePower(t) : 45;
        // Every third physics step, so the dots spread out along the arc.
        const dots = previewPath(power, charge ? 24 : 15).filter((_, i) => i % 3 === 2);
        dots.forEach(([x, y], i) => {
          ctx.globalAlpha = (1 - i / (dots.length + 2)) * (charge ? 1 : 0.6);
          ctx.fillStyle = charge ? `hsl(${120 - power * 1.2}, 90%, 50%)` : color;
          ctx.strokeStyle = "rgba(17,24,39,0.5)";
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(x * s, y * s, i === 0 ? 3.5 : 3, 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
        });
        ctx.globalAlpha = 1;
      }

      // The banner meter shows power; the arc dots above take its colour. Full power
      // waits for the release rather than firing itself.
      // Just under the feet, for the first few throws only; the banner says it too.
      if (spell.input === "charge" && throwsSeen < 3) {
        const text = charge ? "let go to throw · right-click cancels" : "hold to charge";
        const y = (wizard.y + 1) * s + 14 + Math.sin(t / 200);
        ctx.font = "bold 11px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "white";
        ctx.strokeText(text, ox, y);
        ctx.fillStyle = "#111827";
        ctx.fillText(text, ox, y);
      }
    };

    const drawTurnMarker = (t: number) => {
      if (!shown || animation || shown.phase !== "arena_aim") return;
      const unit = shown.units.find((u) => u.id === shown!.current_id);
      if (!unit) return;
      const s = scale();
      // Follows the wizard as drawn, so it rides along mid-jump.
      const [ux, uy] = drawn.get(unit.id) ?? [unit.x, unit.y];
      const cx = (ux + 0.5) * s;
      // Over the name drawLabels prints (its caps reach about 14px above the plate's
      // top), clear of it even at the bottom of its bob.
      const top = (uy + 1) * s - (LABEL_TALL * s + 3);
      const y = top - 28 + Math.sin(t / 180) * 3;
      ctx.fillStyle = shown.players[unit.id]?.color ?? "#111827";
      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(cx - 7, y);
      ctx.lineTo(cx + 7, y);
      ctx.lineTo(cx, y + 9);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    };

    const burst = (x: number, y: number, color: string, count: number, power: number) => {
      for (let i = 0; i < count; i++) {
        const a = Math.random() * Math.PI * 2;
        const v = Math.random() * power;
        const max = 400 + Math.random() * 500;
        particles.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - power * 0.3, life: max, max, color, size: 2 + Math.random() * 3 });
      }
    };

    const shake = (power: number, ms: number) => {
      shakePower = Math.max(shakePower, power);
      shakeUntil = Math.max(shakeUntil, performance.now() + ms);
    };

    // Steps elapsed in the server's simulation timeline.
    const castStep = (now: number, since: number) => {
      const p = shown!.physics;
      return ((now - since) / 1000) * (p.playback_speed / p.dt);
    };

    // Steps of knockback played since `since`. A knockout opens its knockback in slow
    // motion, a third of the speed for KO_SLOW ms, then eases back to full speed over
    // the next KO_SLOW ms, so the hit lands hard without the whole flight crawling.
    const KO_SLOW = 250;
    const knockStep = (now: number, since: number, cast: Cast) => {
      const t = now - since;
      if (!cast.ko?.length) return castStep(now, since);
      const u = Math.min(Math.max(0, t - KO_SLOW), KO_SLOW);
      const played = 0.35 * Math.min(t, KO_SLOW) + 0.35 * u + (0.65 * u * u) / (2 * KO_SLOW) + Math.max(0, t - 2 * KO_SLOW);
      return castStep(since + played, since);
    };

    const pointAt = (path: [number, number][], index: number) => {
      const last = path.length - 1;
      const i = Math.max(0, Math.min(Math.floor(index), last));
      const f = Math.min(1, Math.max(0, index - i));
      const [x0, y0] = path[i];
      const [x1, y1] = path[Math.min(i + 1, last)];
      return [x0 + (x1 - x0) * f, y0 + (y1 - y0) * f];
    };

    // Shows the hits the flight has reached on the board still on screen, so health
    // drops and damage numbers pop as each wizard is struck.
    const applyHits = (step: number) => {
      if (!animation || !shown) return;
      const due = new Map<string, Hit>();
      while (animation.hits.length && animation.hits[0].at <= step) {
        const hit = animation.hits.shift()!;
        due.set(hit.id, hit);
      }
      if (!due.size) return;
      // The health bars along the bottom drop with it too, once the explosion has
      // played out: the page update they need costs a frame, a hitch in mid-blast.
      const shownHits = { cast: animation.cast.id, hits: [...due.values()].map(({ id, hp }) => ({ id, hp })) };
      setTimeout(() => this.pushEvent("arena_hits_shown", shownHits), BOOM_MS * BOOM_FRAMES + 40);
      const next = {
        ...shown,
        units: shown.units.map((u) => {
          const hit = due.get(u.id);
          return hit ? { ...u, hp: hit.hp } : u;
        }),
      };
      announceChanges(shown, next);
      shown = next;
    };

    // Carves a blast's crater into the land on screen the moment it lands, by the server's
    // rule (a cell goes when its centre is inside the circle), instead of waiting for the
    // whole cast to finish. The painted land is cut in place: repainting it all takes a
    // few hundred milliseconds, a visible freeze right on the hit. When the server's land
    // arrives it matches these cells, so it is not repainted either.
    const carve = (cx: number, cy: number, r: number) => {
      if (!shown || !cells) return;
      for (let y = Math.max(0, Math.floor(cy - r)); y <= Math.min(shown.height - 1, Math.ceil(cy + r)); y++) {
        for (let x = Math.max(0, Math.floor(cx - r)); x <= Math.min(shown.width - 1, Math.ceil(cx + r)); x++) {
          if ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r) cells[y * shown.width + x] = 0;
        }
      }
      if (terrainCanvas && terrainRes === LAND_RES) {
        carveLand(terrainCanvas, cx, cy, r);
        if (cx - r < EDGE_FADE || cx + r > shown.width - EDGE_FADE || (ceiling && cy - r < 24)) buildEdges();
      } else landDirty = true;
    };

    // A blast lands, all on the same frame: the fireball and ring flash out, the crater
    // opens with a scorched rim, chunks of the land and smoke fly, and the view punches in.
    const impact = (x: number, y: number, radius: number, color: string) => {
      const s = scale();
      rings.push({ x: x * s, y: y * s, r: (radius + 2) * s * 1.5, born: performance.now(), color });
      booms.push({ x: x * s, y: y * s, size: (radius + 3) * s * 2.6, born: performance.now(), flip: Math.random() < 0.5 ? -1 : 1 });
      kick(Math.min(0.09, 0.015 + radius * 0.006));
      const pal = palette();
      const land = [...pal.grass.slice(0, 2), ...pal.soil, ...pal.rock.slice(0, 2)];
      // Clods of the land itself, a cell or two across, thrown out of the hole. They
      // bounce where they come down and lie there a moment, so the ground visibly went somewhere.
      for (let i = 0; i < 6 + radius * 2; i++) {
        const a = -Math.PI * (0.08 + Math.random() * 0.84);
        const v = 70 + Math.random() * (80 + radius * 20);
        const [r, g, b] = land[i % land.length];
        const max = 1800 + Math.random() * 1200;
        const size = s * (i % 3 === 0 ? 1.4 + Math.random() * 1.2 : 0.6 + Math.random() * 0.7);
        const shape = Array.from({ length: 6 }, () => 0.7 + Math.random() * 0.45);
        particles.push({ x: x * s, y: y * s, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: max, max, color: `rgb(${r},${g},${b})`, size, chunk: true, shape, bounces: 0 });
      }
      const wind = shown?.wind ?? 0;
      for (let i = 0; i < 4 + radius; i++) {
        const max = 1600 + Math.random() * 1400;
        smokes.push({
          x: x * s + (Math.random() - 0.5) * radius * s,
          y: y * s - Math.random() * radius * s * 0.6,
          r: 4 + Math.random() * radius * 1.4,
          vx: wind * 4 + (Math.random() - 0.5) * 10,
          vy: -10 - Math.random() * 12,
          life: max,
          max,
        });
      }
      scorches.push({ x, y, r: radius });
      if (scorches.length > 80) scorches = scorches.slice(-80);
      carve(x, y, radius);
    };

    // The painted explosion plays through its frames: a flash, the fireball swelling to
    // its peak, then breaking up into smoke that drifts off. The frames are very different
    // drawings 85 ms apart, so each one is mixed into the next on a scratch canvas (added
    // together, weighted, so the blend stays solid where both are) while the cloud keeps
    // swelling: one motion instead of a cut every frame.
    const BOOM_MS = 85;
    let boomMix: HTMLCanvasElement | null = null;
    const drawBooms = (now: number) => {
      booms = booms.filter((b) => now - b.born < BOOM_MS * BOOM_FRAMES);
      const img = art.boom;
      if (!ready(img)) return;
      boomMix ??= Object.assign(document.createElement("canvas"), { width: BOOM_CELL, height: BOOM_CELL });
      const mix = boomMix.getContext("2d")!;
      for (const b of booms) {
        const age = Math.max(0, now - b.born);
        const at = age / BOOM_MS;
        const n = Math.min(BOOM_FRAMES - 1, Math.floor(at));
        const f = n + 1 < BOOM_FRAMES ? at - n : 0;
        const grow = 0.7 + (1 - (1 - Math.min(1, age / (BOOM_MS * 3))) ** 3) * 0.42 + (0.1 * at) / BOOM_FRAMES;
        const size = b.size * grow;
        const fade = at >= 5 ? Math.max(0, 1 - (age - BOOM_MS * 5) / (BOOM_MS * 3)) : 1;
        mix.globalCompositeOperation = "copy";
        mix.globalAlpha = 1 - f;
        mix.drawImage(img, n * BOOM_CELL, 0, BOOM_CELL, BOOM_CELL, 0, 0, BOOM_CELL, BOOM_CELL);
        if (f > 0) {
          mix.globalCompositeOperation = "lighter";
          mix.globalAlpha = f;
          mix.drawImage(img, (n + 1) * BOOM_CELL, 0, BOOM_CELL, BOOM_CELL, 0, 0, BOOM_CELL, BOOM_CELL);
        }
        ctx.save();
        ctx.translate(b.x, b.y - size * 0.12 * (at / BOOM_FRAMES));
        ctx.scale(b.flip, 1);
        ctx.globalAlpha = fade;
        ctx.drawImage(boomMix, -size / 2, -size / 2, size, size);
        ctx.restore();
      }
      ctx.globalAlpha = 1;
    };

    const drawRings = (now: number) => {
      rings = rings.filter((ring) => now - ring.born < 320);
      for (const ring of rings) {
        const k = Math.max(0, (now - ring.born) / 320);
        if (k === 0 && now < ring.born) {
          // The frozen beat: a white-hot core where the blast is about to go off.
          ctx.fillStyle = "rgba(255,255,255,0.9)";
          ctx.beginPath();
          ctx.arc(ring.x, ring.y, ring.r * 0.35, 0, Math.PI * 2);
          ctx.fill();
          continue;
        }
        // A fireball that swells and burns out, when the painted explosion isn't loaded.
        if (k < 0.65 && !ready(art.boom)) {
          const f = k / 0.65;
          const fr = ring.r * (0.55 + f * 0.55);
          const g = ctx.createRadialGradient(ring.x, ring.y, 0, ring.x, ring.y, fr);
          g.addColorStop(0, "#fffbeb");
          g.addColorStop(0.3, "#fde047");
          g.addColorStop(0.65, "#f97316");
          g.addColorStop(1, "rgba(234,88,12,0)");
          ctx.globalAlpha = 1 - f * f;
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.arc(ring.x, ring.y, fr, 0, Math.PI * 2);
          ctx.fill();
        }
        ctx.globalAlpha = 1 - k;
        ctx.fillStyle = "rgba(255,255,255,0.35)";
        ctx.beginPath();
        ctx.arc(ring.x, ring.y, ring.r * (0.3 + k * 0.7), 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = "#fff";
        ctx.lineWidth = 4 * (1 - k) + 1;
        ctx.stroke();
        ctx.strokeStyle = ring.color;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(ring.x, ring.y, ring.r * (0.2 + k * 0.85), 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    };

    const drawSmoke = (dt: number) => {
      smokes = smokes.filter((m) => (m.life -= dt) > 0);
      for (const m of smokes) {
        const k = 1 - m.life / m.max;
        m.x += m.vx * (dt / 1000);
        m.y += m.vy * (dt / 1000);
        m.vy *= 0.995;
        ctx.globalAlpha = 0.45 * (1 - k) * Math.min(1, k * 8);
        ctx.fillStyle = k < 0.15 ? "#78716c" : "#a8a29e";
        ctx.beginPath();
        ctx.arc(m.x, m.y, m.r * (1 + k * 1.8), 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    };

    // How each spell looks in flight: its painted sprite, turned the way it flies (or
    // spinning, or hopping), with a trail; beams and swings are drawn as what they are.
    // Sprites painted heading somewhere turn to fly that way (the shrimp falls down and
    // to the left); round ones spin as they go; the fly and the crab face the way they go.
    const ORIENT: Record<string, number> = { starfall: (3 * Math.PI) / 4 };
    const SPINS = new Set(["firebolt", "fuserune", "embers", "thunderegg", "meteors", "surge", "holyorb"]);
    const SIZE: Record<string, number> = { firebolt: 22, fuserune: 18, embers: 14, thunderegg: 20, seeker: 22, hexhare: 24, holyorb: 28, anvil: 48, meteors: 26, starfall: 24, surge: 24, blastrune: 22, slab: 40 };
    const drawProjectile = (segment: Segment, local: number, x: number, y: number, color: string, cast: Cast) => {
      const s = scale();
      const id = segment.spell === "surge" ? "meteors" : segment.spell;
      const [px, py] = pointAt(segment.path, Math.max(0, local - 0.6));
      const heading = Math.atan2(y - py, x - px);

      if (id === "lance") {
        // The quill flies point first with a pink streak behind it.
        const [sx, sy] = segment.path[0];
        const streak = ctx.createLinearGradient(sx * s, sy * s, x * s, y * s);
        streak.addColorStop(0, "rgba(236,72,153,0)");
        streak.addColorStop(1, color);
        ctx.strokeStyle = streak;
        ctx.lineWidth = 3;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(sx * s, sy * s);
        ctx.lineTo(x * s, y * s);
        ctx.stroke();
        sprite("lance", x * s, y * s, 26, heading);
        if (frame % 2 === 0) burst(x * s, y * s, "#fbcfe8", 1, 30);
        return;
      }
      if (id === "tunnel") {
        const [tx, ty] = pointAt(segment.path, Math.max(0, local - 4));
        ctx.strokeStyle = color;
        ctx.lineWidth = 6;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(tx * s, ty * s);
        ctx.lineTo(x * s, y * s);
        ctx.stroke();
        sprite("tunnel", x * s, y * s, 22, heading);
        if (frame % 2 === 0) burst(x * s, y * s, "#a16207", 3, 50);
        return;
      }
      if (id === "hook") {
        // The shrimp flies out on its line, swinging a little.
        const [ox, oy] = segment.path[0];
        chain(ox * s, oy * s, x * s, y * s);
        sprite("hook", x * s, y * s, 26, Math.sin(now() / 90) * 0.3);
        return;
      }
      if (id === "blastrune") {
        // The egg rolls without a trail, turning as far as it has rolled. When it goes
        // off it is already drawn where it lies.
        if (segment.radius === 0) drawEgg(x * s, y * s, (x - segment.path[0][0]) / eggR(), eggSize());
        return;
      }
      if (id === "blink") {
        const [fx0, fy0] = segment.path[0];
        sprite("blink", fx0 * s, fy0 * s, 34, now() / 120);
        sprite("blink", x * s, y * s, 34, -now() / 120);
        return;
      }

      const size = SIZE[id] ?? 20;
      // A tapering trail in the spell's colour, so even a small shot reads as it flies.
      ctx.lineCap = "round";
      for (let i = 1; i <= 7; i++) {
        const [ax, ay] = pointAt(segment.path, Math.max(0, local - i * 0.8));
        const [bx, by] = pointAt(segment.path, Math.max(0, local - (i - 1) * 0.8));
        ctx.globalAlpha = 0.5 * (1 - i / 8);
        ctx.strokeStyle = color;
        ctx.lineWidth = size * 0.7 * (1 - i / 9);
        ctx.beginPath();
        ctx.moveTo(ax * s, ay * s);
        ctx.lineTo(bx * s, by * s);
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
      if (frame % 2 === 0) burst(x * s, y * s, color, 1, 20);

      let angle = 0;
      let flip = 1;
      if (id in ORIENT) angle = heading - ORIENT[id];
      else if (id === "hexhare" || id === "seeker") flip = x >= px ? 1 : -1;
      else if (SPINS.has(id)) angle = local * 0.3 * (x >= px ? 1 : -1);
      if (id === "holyorb") {
        // It sings as it flies: a halo of light around it.
        const glow = ctx.createRadialGradient(x * s, y * s, 2, x * s, y * s, size * 1.3);
        glow.addColorStop(0, "rgba(254, 240, 138, 0.8)");
        glow.addColorStop(1, "rgba(254, 240, 138, 0)");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(x * s, y * s, size * 1.3, 0, Math.PI * 2);
        ctx.fill();
      }
      if (!sprite(id, x * s, y * s, size, angle, flip)) {
        ctx.fillStyle = color;
        ctx.strokeStyle = "#111827";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(x * s, y * s, size / 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }
      void cast;
    };
    const now = () => performance.now();

    // A flight ending without a blast: a bounce, a hop, a slab or keg set down, a blink.
    const landed = (segment: Segment, x: number, y: number, color: string, _cast: Cast) => {
      const s = scale();
      if (!segment.hit) {
        burst(x * s, y * s, "#bfdbfe", 18, 80);
        return;
      }
      if (segment.spell === "hook") {
        const [ex, ey] = segment.path[segment.path.length - 1];
        burst(ex * s, ey * s, "#fff", 18, 120);
        rings.push({ x: ex * s, y: ey * s, r: 20, born: performance.now(), color });
        floaters.push({ x: ex * s, y: (ey - 4) * s, text: "CAN'T RESIST!", color: "#fde047", size: 22, life: 900, max: 900 });
        kick(0.04);
        shake(5, 200);
        return;
      }
      if (segment.spell === "blink") {
        burst(x * s, y * s, colorOf("blink", "#a855f7"), 40, 120);
        return;
      }
      // A skip or hop: a puff of dust where it touched down.
      burst(x * s, y * s, "#d6d3d1", 10, 60);
      burst(x * s, y * s, color, 6, 40);
    };

    const drawFlight = (now: number) => {
      if (!animation || !shown) return;
      const { cast } = animation;
      const s = scale();
      const step = castStep(now, animation.start);
      applyHits(step);

      // A grand spell marks where it will land while its title card plays.
      const first = cast.segments[0];
      if (cast.grand && first && step < 0) {
        const [tx, ty] = first.path[first.path.length - 1];
        const pulse = 0.5 + 0.5 * Math.sin(now / 70);
        ctx.strokeStyle = `rgba(239, 68, 68, ${0.5 + 0.4 * pulse})`;
        ctx.fillStyle = "rgba(239, 68, 68, 0.15)";
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.ellipse(tx * s, ty * s, Math.max(first.radius, 6) * s, Math.max(first.radius, 6) * s * 0.3, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }

      cast.segments.forEach((segment, n) => {
        const local = step - segment.start;
        const last = segment.path.length - 1;
        const color = colorOf(segment.spell, "#f97316");
        if (local < 0) return;

        if (local < last) {
          const [x, y] = pointAt(segment.path, local);

          drawProjectile(segment, local, x, y, color, cast);
        } else if (!animation!.landed.has(n)) {
          animation!.landed.add(n);
          sounds.land(segment);
          const [x, y] = segment.path[last];
          if (segment.hit && segment.radius > 0 && segment.spell === "holyorb") {
            // The grand impact: a white flash, a beat of stillness, then the blast and a glowing scar.
            flashUntil = now + 220;
            animation!.start += 140;
            burst(x * s, y * s, "#fff", 40, 320);
            burst(x * s, y * s, "#fde047", 90, 300);
            burst(x * s, y * s, color, 70, 260);
            shake(16, 1000);
            scars.push({ x, y, r: segment.radius + 1, born: now });
            carve(x, y, segment.radius);
          } else if (segment.hit && segment.radius > 0) {
            impact(x, y, segment.radius, color);
            burst(x * s, y * s, "#fde047", 20 + segment.radius * 4, 100 + segment.radius * 12);
            burst(x * s, y * s, color, 16 + segment.radius * 3, 80 + segment.radius * 10);
            const heavy = segment.spell === "anvil" || segment.spell === "blastrune" || segment.radius >= 10;
            shake(heavy ? 14 : Math.min(10, segment.radius * 1.1), heavy ? 520 : 340);
          } else {
            landed(segment, x, y, color, cast);
          }
        }
      });

      if (step >= cast.flight_steps) {
        animation.aftermathAt = now;
        if (cast.shake) shake(6, 700);
        sounds.aftermath(cast);
        for (const aura of cast.auras ?? []) {
          const unit = (pending ?? shown)?.units.find((u) => u.id === aura.id);
          if (unit) {
            const s = scale();
            burst((unit.x + 0.5) * s, (unit.y + 1) * s, colorOf(aura.kind, "#fff"), 26, 70);
            burst((unit.x + 0.5) * s, (unit.y + 1) * s, "#fde68a", 14, 50);
          }
        }
        if (pending) {
          show(pending, new Set(cast.ko ?? []));
          pending = null;
          castLocked = true;
        }
      }
    };

    // Where each knocked unit is right now while the aftermath plays. One whose knockback
    // is over stays where it stopped (against a wall, say) until the cast ends, then drops
    // from there like any fall.
    const knockedPositions = (now: number, flying = false) => {
      const positions = new Map<string, [number, number]>();
      if (!animation || animation.aftermathAt === null) return positions;
      const step = knockStep(now, animation.aftermathAt, animation.cast);
      for (const knock of animation.cast.knocks) {
        const last = knock.path.length - 1;
        if (step < last || (!flying && last >= 0)) positions.set(knock.id, pointAt(knock.path, Math.min(step, last)) as [number, number]);
      }
      return positions;
    };

    const drawAftermath = (now: number) => {
      if (!animation || animation.aftermathAt === null || !shown) return;
      const { cast } = animation;
      const elapsed = now - animation.aftermathAt;
      const step = knockStep(now, animation.aftermathAt, cast);

      // A tempted flamingo lunges after the shrimp on its line until it lands.
      if (cast.spell === "hook") {
        const s = scale();
        const caster = shown.units.find((u) => u.id === cast.caster_id);
        for (const knock of cast.knocks) {
          if (!caster || step >= knock.path.length - 1) continue;
          const [kx, ky] = pointAt(knock.path, step);
          const [cx, cy] = drawn.get(caster.id) ?? [caster.x, caster.y];
          chain((cx + 0.5) * s, (cy - 1) * s, (kx + 0.5) * s, (ky - 1.5) * s);
          sprite("hook", (kx + 0.5) * s, (ky - 1.5) * s, 22, Math.sin(now / 90) * 0.3);
        }
      }

      // A knocked-out wizard falls when their knockback ends, or at once if nothing knocked them.
      let fell = false;
      for (const id of cast.ko ?? []) {
        const knock = cast.knocks.find((k) => k.id === id);
        if (animation.koShown.has(id) || (knock && step < knock.path.length - 1)) continue;
        animation.koShown.add(id);
        animation.koAt ??= now;
        const unit = shown.units.find((u) => u.id === id);
        // Stopped by a wall above where it ends up: the KO waits until it lands there.
        const end = knock?.path[knock.path.length - 1];
        const final = pending?.units.find((u) => u.id === id);
        if (unit && end && final && final.y - end[1] > 2 && Math.abs(final.x - end[0]) <= 2) {
          fallKO.add(id);
          fallHurt.set(id, final.hp - unit.hp);
          continue;
        }
        if (unit) floatText(unit, "KO!", "#dc2626", 30);
        fell = true;
      }
      if (fell) {
        shake(10, 900);
        sounds.knockout();
      }

      const knockSteps = Math.max(0, ...cast.knocks.map((k) => k.path.length));
      const done =
        step >= knockSteps &&
        (animation.koAt !== null ? now - animation.koAt > 700 : elapsed > 400);

      if (done) {
        animation = null;
        castLocked = false;
        if (pending) {
          const next = pending;
          pending = null;
          receive(next);
        }
        while (!animation && backlog.length) receive(backlog.shift()!);
      }
    };

    const drawParticles = (dt: number) => {
      particles = particles.filter((p) => (p.life -= dt) > 0);
      const s = scale();
      for (const p of particles) {
        const resting = p.chunk && (p.bounces ?? 0) >= 3;
        if (!resting) {
          p.vy += (p.chunk ? 420 : 220) * (dt / 1000);
          p.x += p.vx * (dt / 1000);
          p.y += p.vy * (dt / 1000);
          // Clods tumble with their sideways speed, so they stop turning as they settle.
          p.rot = (p.rot ?? 0) + (p.vx * dt) / 3000;
        }
        // A clod that comes down on land bounces, loses most of its speed, and settles.
        // Not in its first moments: the hole it flew out of may not be carved yet.
        if (p.chunk && !resting && p.vy > 0 && p.max - p.life > 150) {
          const foot = p.y + p.size * 0.4;
          if (solidAt(Math.floor(p.x / s), Math.floor(foot / s))) {
            p.y -= p.vy * (dt / 1000);
            p.vy = -p.vy * 0.32;
            p.vx *= 0.5;
            p.bounces = Math.abs(p.vy) < 25 ? 3 : (p.bounces ?? 0) + 1;
          }
        }
        // Clods stay solid until their last half second; sparks fade all along.
        ctx.globalAlpha = p.chunk ? Math.min(1, p.life / 500) : Math.max(0, p.life / p.max);
        ctx.fillStyle = p.color;
        if (p.chunk) {
          ctx.save();
          ctx.translate(p.x, p.y);
          ctx.rotate(p.rot ?? 0);
          const shape = p.shape ?? [1, 1, 1, 1, 1, 1];
          ctx.beginPath();
          shape.forEach((k, i) => {
            const a = (i / shape.length) * Math.PI * 2;
            ctx.lineTo(Math.cos(a) * k * p.size * 0.5, Math.sin(a) * k * p.size * 0.5);
          });
          ctx.closePath();
          ctx.fill();
          ctx.strokeStyle = "#1c1917";
          ctx.lineWidth = Math.max(1, p.size * 0.14);
          ctx.stroke();
          ctx.restore();
        } else {
          ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
        }
      }
      ctx.globalAlpha = 1;
    };

    // What the camera should look at: the flying spell, then whoever got knocked,
    // then the wizard whose turn it is. Free look pauses following between casts.
    const cameraFocus = (now: number): [number, number] | null => {
      if (!shown) return null;
      // The intro visits each flamingo as it drops in, starting where the first will.
      if (shown.phase === "arena_loading" || shown.phase === "arena_intro") {
        const order = introOrder();
        const i = introAt === null ? 0 : Math.min(order.length - 1, Math.floor((now - introAt) / introStep()));
        const unit = shown.units.find((u) => u.id === order[i]);
        if (unit) return [unit.x + 0.5, unit.y - 4];
      }
      if (animation && animation.aftermathAt === null) {
        const step = castStep(now, animation.start);
        // While a grand spell's title card plays, look at where it will land.
        const first = animation.cast.segments[0];
        if (step < 0 && animation.cast.grand && first) return first.path[first.path.length - 1];
        for (const segment of animation.cast.segments) {
          const local = step - segment.start;
          if (local >= 0 && local < segment.path.length) return pointAt(segment.path, local) as [number, number];
        }
      }
      if (animation && animation.aftermathAt !== null) {
        const knocked = [...knockedPositions(now, true).values()];
        if (knocked.length) return knocked[0];
        // Nobody flew: hold on where the spell ended so the blast is seen before
        // the camera heads back.
        const last = animation.cast.segments.reduce<(typeof animation.cast.segments)[number] | null>(
          (a, b) => (!a || b.start + b.path.length > a.start + a.path.length ? b : a),
          null,
        );
        if (last?.path.length) return last.path[last.path.length - 1] as [number, number];
      }
      if (now < freeLookUntil && !animation) return null;
      // A flamingo falling (its broom spent as the turn ends, say) is watched until it lands.
      for (const id of falls.keys()) {
        const at = drawn.get(id);
        if (at) return [at[0] + 0.5, at[1] - 4];
      }
      const unit = shown.units.find((u) => u.id === shown!.current_id && !u.dead);
      // As drawn, so the camera rides along a jump instead of waiting where it lands.
      const at = unit && (drawn.get(unit.id) ?? [unit.x, unit.y]);
      return at ? [at[0] + 0.5, at[1] - 4] : null;
    };

    const moveCamera = (now: number, dt: number) => {
      if (!shown) return;
      // Ease the zoom, keeping the middle of the view where it was.
      const want = zoomTarget * (charge ? 0.85 : 1);
      if (Math.abs(want - zoom) > 0.001) {
        const cx = cam.x + VIEW_W / 2;
        const cy = cam.y + VIEW_H / 2;
        zoom += (want - zoom) * (1 - Math.exp(-dt / 160));
        fitView();
        cam.x = cx - VIEW_W / 2;
        cam.y = cy - VIEW_H / 2;
      }
      dockPad = measureDock();
      // Pointer at the left or right edge pans the view, Worms style.
      if (pointer && edgeArmed && !charge && !animation) {
        const edge = 24;
        const dir = pointer.x < edge ? -1 : pointer.x > W - edge ? 1 : 0;
        if (dir !== 0) {
          cam.x += dir * dt * 0.06;
          freeLookUntil = now + 2500;
        }
      }
      const focus = cameraFocus(now);
      if (focus) {
        const tx = focus[0] - VIEW_W / 2;
        // Frame the focus in the part of the view the dock doesn't cover.
        const ty = focus[1] - (VIEW_H - dockPad) * 0.55;
        if (!camReady) {
          cam.x = tx;
          cam.y = ty;
          camReady = true;
        } else {
          // Eased enough to follow a spell without whipping from caster to impact and back.
          const k = 1 - Math.exp(-dt / (animation || shown.phase === "arena_intro" ? 260 : 380));
          cam.x += (tx - cam.x) * k;
          cam.y += (ty - cam.y) * k;
        }
      }
      clampCam();
    };

    // Where a jumping wizard is along its arc; it kicks up dust where it lands.
    const jumpPosition = (unit: Unit, now: number) => {
      if (!jumping || jumping.id !== unit.id || !shown) return null;
      const { path } = jumping;
      const p = shown.physics;
      const step = ((now - jumping.start) / 1000) * (p.playback_speed / p.dt);
      if (step < path.length - 1) return pointAt(path, step) as [number, number];
      jumping = null;
      drawn.set(unit.id, [unit.x, unit.y]);
      touchDown(unit, unit.x, now);
      return null;
    };

    // Feet on the ground after a jump or a drop: dust, a thump, a squash, and the fall
    // damage held back until now.
    const touchDown = (unit: Unit, x: number, now: number) => {
      landedAt.set(unit.id, now);
      const s = scale();
      if (fallKO.delete(unit.id)) {
        // Into the sea: a splash, then the KO.
        fallHurt.delete(unit.id);
        burst((x + 0.5) * s, (unit.y + 0.5) * s, "#e0f2fe", 26, 110);
        burst((x + 0.5) * s, (unit.y + 0.5) * s, "#f9a8d4", 8, 60);
        floatText(unit, "KO!", "#dc2626", 30);
        sounds.knockout();
        shake(10, 600);
        return;
      }
      burst((x + 0.5) * s, (unit.y + 1) * s, "#a8a29e", 10, 50);
      sounds.landed();
      const hurt = fallHurt.get(unit.id);
      if (hurt === undefined) return;
      fallHurt.delete(unit.id);
      hurtAt.set(unit.id, now);
      floatText(unit, `${hurt}`, "#ef4444", hurt <= -30 ? 24 : 18);
      sounds.hurt(-hurt);
      shake(Math.min(8, -hurt / 8), 300);
    };

    const glide = (unit: Unit, dt: number) => {
      const s = scale();
      const prev = drawn.get(unit.id);
      if (!prev || (unit.dead && !fallKO.has(unit.id))) {
        drawn.set(unit.id, [unit.x, unit.y]);
        return { x: unit.x, y: unit.y };
      }
      // A long jump is a teleport, unless it is straight down: that is a fall.
      const drop = unit.y > prev[1] && Math.abs(unit.x - prev[0]) <= 2;
      if (!drop && Math.hypot(unit.x - prev[0], unit.y - prev[1]) > 6) {
        sounds.teleport();
        const color = colorOf("blink", "#a855f7");
        burst((prev[0] + 0.5) * s, (prev[1] - 1) * s, color, 30, 90);
        burst((unit.x + 0.5) * s, (unit.y - 1) * s, color, 40, 120);
        burst((unit.x + 0.5) * s, (unit.y - 1) * s, "#fff", 16, 60);
        drawn.set(unit.id, [unit.x, unit.y]);
        return { x: unit.x, y: unit.y };
      }
      // Walking and flight both close on the next cell at a steady speed, a little
      // faster than the steps arrive, so the flamingo glides instead of lurching once a
      // cell. Each axis keeps its own pace, so a diagonal keeps up with its steps, and a
      // long way behind closes faster.
      const pace = (unit.float ?? 0) > 0 ? FLY_MS : STEP_MS;
      const chase = (from: number, to: number) => {
        const d = Math.abs(to - from);
        const move = Math.min(d, Math.max((dt / pace) * 1.08, d * (1 - Math.exp(-dt / 140))));
        return from + Math.sign(to - from) * move;
      };
      const x = chase(prev[0], unit.x);
      let y = chase(prev[1], unit.y);
      // A drop (off a ledge, or the ground blasted away) speeds up to the flamingo's top
      // speed, braking at each flap, and lands with a squash and any fall damage.
      const now = performance.now();
      const fall = falls.get(unit.id);
      if ((unit.float ?? 0) <= 0 && unit.y > prev[1] && (fall || unit.y - prev[1] > 2)) {
        const p = shown!.physics;
        const f = fall ?? { v: 0, at: now };
        f.v = flapping(now - f.at)
          ? f.v * Math.exp(-dt / 150)
          : Math.min(FALL_TOP, f.v + ((FALL_GRAVITY * p.gravity * p.playback_speed ** 2) / 1e6) * dt);
        y = Math.min(unit.y, prev[1] + f.v * dt);
        if (y < unit.y) falls.set(unit.id, f);
        else {
          falls.delete(unit.id);
          touchDown(unit, x, now);
        }
      } else {
        falls.delete(unit.id);
        // Held damage whose drop never played (the flamingo was moved instead) shows now.
        if (fallHurt.has(unit.id) && jumping?.id !== unit.id) touchDown(unit, x, now);
      }
      if ((unit.float ?? 0) > 0) {
        drawn.set(unit.id, [x, y]);
        return { x, y };
      }
      if (Math.abs(unit.x - x) > 0.05 && frame % 3 === 0) burst((x + 0.5) * s, (unit.y + 1) * s, "#a8a29e", 1, 18);
      drawn.set(unit.id, [x, y]);
      return { x, y };
    };

    // A grand spell darkens the sky, letterboxes the view and slams its name in while it
    // winds up, then lifts once the dust settles. Drawn over the whole arena.
    const drawGrand = (now: number) => {
      if (now < flashUntil) {
        ctx.fillStyle = `rgba(255,255,255,${0.9 * ((flashUntil - now) / 220)})`;
        ctx.fillRect(0, 0, W, H);
      }
      if (!grand) return;
      const elapsed = now - grand.start;
      const intro = shown?.physics.grand_intro_ms ?? 1300;
      const playing = !!animation && animation.cast.grand;
      if (!playing && grandEndedAt === null) grandEndedAt = now;
      const fade = playing ? Math.min(1, elapsed / 300) : Math.max(0, 1 - (now - grandEndedAt!) / 700);
      if (!playing && fade <= 0) {
        grand = null;
        grandEndedAt = null;
        return;
      }
      ctx.save();
      ctx.fillStyle = `rgba(76, 5, 25, ${0.35 * fade})`;
      ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = "#111827";
      ctx.fillRect(0, 0, W, 34 * fade);
      ctx.fillRect(0, H - 34 * fade, W, 34);
      if (elapsed < intro + 200) {
        const a = elapsed - 150;
        const slam = a < 120 ? 1.6 - 0.6 * Math.max(0, a / 120) : 1;
        ctx.globalAlpha = Math.max(0, Math.min(1, a / 60, (intro + 200 - elapsed) / 250));
        ctx.translate(W / 2, H * 0.3);
        ctx.scale(slam, slam);
        ctx.textAlign = "center";
        ctx.font = "900 60px ui-sans-serif, system-ui";
        ctx.lineWidth = 10;
        ctx.strokeStyle = "#111827";
        ctx.strokeText(grand.name.toUpperCase(), 0, 0);
        ctx.fillStyle = grand.color;
        ctx.fillText(grand.name.toUpperCase(), 0, 0);
        ctx.font = "900 16px ui-sans-serif, system-ui";
        ctx.lineWidth = 5;
        ctx.strokeText("GRAND SPELL", 0, 28);
        ctx.fillStyle = "#fde047";
        ctx.fillText("GRAND SPELL", 0, 28);
      }
      ctx.restore();
    };
    let grandEndedAt: number | null = null;

    const drawKnockoutBanner = (now: number) => {
      if (!animation || animation.koAt === null) return;
      const elapsed = now - animation.koAt;
      const pulse = 1 + 0.08 * Math.sin(elapsed / 90);
      ctx.save();
      ctx.globalAlpha = Math.min(1, elapsed / 250);
      ctx.fillStyle = "rgba(17, 24, 39, 0.18)";
      ctx.fillRect(0, 0, W, H);
      ctx.translate(W / 2, H * 0.28);
      ctx.scale(pulse, pulse);
      ctx.font = "900 54px ui-sans-serif, system-ui";
      ctx.textAlign = "center";
      ctx.lineWidth = 8;
      ctx.strokeStyle = "#111827";
      ctx.strokeText("KNOCKOUT!", 0, 0);
      ctx.fillStyle = "#facc15";
      ctx.fillText("KNOCKOUT!", 0, 0);
      ctx.restore();
    };

    // Off-screen wizards get a labelled arrow at the edge; clicking one looks at them.
    let markers: { id: string; x: number; y: number; w: number; h: number }[] = [];
    const drawOffscreenMarkers = () => {
      markers = [];
      if (!shown) return;
      const sides: Record<string, { unit: Unit; y: number }[]> = { left: [], right: [] };
      // On-screen wizards (body and name), which markers must not cover.
      const visible: { x: number; top: number; bottom: number }[] = [];
      for (const unit of shown.units) {
        if (unit.dead || unit.kind !== "wizard" || unspawned(unit.id, performance.now())) continue;
        const px = CELL * zoom;
        const sx = (unit.x + 0.5 - cam.x) * px;
        if (sx >= 0 && sx <= W) {
          visible.push({ x: sx, top: (unit.y - 4 - cam.y) * px - 28 * zoom, bottom: (unit.y + 1 - cam.y) * px });
          continue;
        }
        sides[sx < 0 ? "left" : "right"].push({ unit, y: Math.max(24, Math.min(H - 24, (unit.y - 1 - cam.y) * px)) });
      }
      ctx.save();
      ctx.font = "bold 12px ui-sans-serif, system-ui";
      ctx.textBaseline = "middle";
      for (const [side, list] of Object.entries(sides)) {
        const left = side === "left";
        // Stack markers that would overlap, and step around on-screen wizards near this edge.
        list.sort((a, b) => a.y - b.y);
        const near = visible.filter((v) => (left ? v.x < 190 : v.x > W - 190));
        for (let i = 0; i < list.length; i++) {
          const floor = i > 0 ? list[i - 1].y + 26 : -Infinity;
          let y = Math.max(list[i].y, floor);
          for (const v of near) {
            if (y + 11 < v.top || y - 11 > v.bottom) continue;
            y = v.top - 12 >= Math.max(floor, 12) ? v.top - 12 : v.bottom + 12;
          }
          list[i].y = y;
        }
        for (const { unit, y } of list) {
          const name = shown.players[unit.id]?.name ?? "";
          const label = name.length > 14 ? `${name.slice(0, 13)}…` : name;
          const w = ctx.measureText(label).width + 30;
          const x = left ? 6 : W - 6 - w;
          ctx.fillStyle = "rgba(255,255,255,0.92)";
          ctx.strokeStyle = "#111827";
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.roundRect?.(x, y - 11, w, 22, 11);
          ctx.fill();
          ctx.stroke();
          ctx.fillStyle = shown.players[unit.id]?.color ?? "#9ca3af";
          const ax = left ? x + 12 : x + w - 12;
          ctx.beginPath();
          ctx.moveTo(ax + (left ? -6 : 6), y);
          ctx.lineTo(ax + (left ? 4 : -4), y - 6);
          ctx.lineTo(ax + (left ? 4 : -4), y + 6);
          ctx.closePath();
          ctx.fill();
          ctx.lineWidth = 1.5;
          ctx.stroke();
          ctx.fillText(label, left ? x + 22 : x + 8, y + 1);
          markers.push({ id: unit.id, x, y: y - 11, w, h: 22 });
        }
      }
      ctx.restore();
    };

    // Looks at a wizard for a while, as if the player had panned there by hand.
    const lookAt = (id: string) => {
      const unit = shown?.units.find((u) => u.id === id && !u.dead);
      if (!unit) return;
      cam.x = unit.x + 0.5 - VIEW_W / 2;
      cam.y = unit.y - (VIEW_H - dockPad) * 0.55;
      clampCam();
      freeLookUntil = performance.now() + 5000;
    };
    // Without an id (as from the tour), it looks at the viewer's own wizard.
    const onFocus = (event: Event) => {
      const id = (event as CustomEvent<{ id?: string } | null>).detail?.id ?? shown?.viewer_id;
      if (id) lookAt(id);
    };

    // Where the viewer's wizard is on screen, for the first-turn tour to point at.
    (canvas as HTMLCanvasElement & { viewerPoint?: () => { x: number; y: number; k: number } | null }).viewerPoint = () => {
      const unit = myWizard();
      if (!unit) return null;
      const r = canvas.getBoundingClientRect();
      const k = (r.width / W) * CELL * zoom;
      const [x, y] = drawn.get(unit.id) ?? [unit.x, unit.y];
      return { x: r.left + (x + 0.5 - cam.x) * k, y: r.top + (y - cam.y) * k, k };
    };

    let lastTime = performance.now();
    let rafId = 0;

    // The server's walking rules, mirrored: a wizard is 3 cells tall, climbs up to
    // max_climb cells a step (6 on a broomstick), then drops to the ground.
    const blockedAt = (x: number, y: number) =>
      !shown || x < 0 || x >= shown.width || solidAt(x, y) || solidAt(x, y - 1) || solidAt(x, y - 2);
    const predictStep = (from: { x: number; y: number }, dir: number, floating: boolean) => {
      if (!shown) return null;
      const x = from.x + dir;
      const climb = floating ? 6 : shown.physics.max_climb ?? 2;
      let y: number | null = null;
      for (let c = 0; c <= climb; c++) {
        if (!blockedAt(x, from.y - c)) {
          y = from.y - c;
          break;
        }
      }
      if (y === null) return null;
      if (!floating) while (y + 1 < shown.height && y < shown.water_level && !solidAt(x, y + 1)) y++;
      return { x, y };
    };

    const walkStep = (now: number) => {
      const wizard = myWizard();
      if (!wizard || !canAct() || jumping || falls.has(wizard.id)) return;
      nextStepAt = now + STEP_MS;
      if (stepsLeft <= 0) return;
      const from = predicted ?? wizard;
      const to = predictStep(from, heldDir, (wizard.float ?? 0) > 0);
      if (!to) {
        heldDir = 0;
        if (now - lastBlockedHint > 2500) {
          lastBlockedHint = now;
          floatText(wizard, "Too steep! W to jump", "#fde68a", 15, 15);
        }
        return;
      }
      predicted = { ...to, at: now };
      stepsLeft -= 1;
      this.pushEvent("walk", { dir: heldDir });
    };

    // One cell of broom flight, by the server's rules: sideways it climbs over a bump of
    // up to 6 cells (`Units.step`), and up or down it stops at rock, the sky's ceiling
    // and the sea (the `:rise` command). Each move costs a step and is sent to confirm.
    const flyStep = (now: number) => {
      const wizard = myWizard();
      if (!shown || !wizard || !canAct()) return;
      // Steps keep a steady rhythm whatever the frame rate; a fresh press starts it.
      nextStepAt = now - nextStepAt > FLY_MS ? now + FLY_MS : nextStepAt + FLY_MS;
      const start = predicted ?? wizard;
      let at: { x: number; y: number } = start;
      if (heldDir && stepsLeft > 0) {
        const to = predictStep(at, heldDir, true);
        if (to) {
          at = to;
          stepsLeft -= 1;
          this.pushEvent("walk", { dir: heldDir });
        }
      }
      const y = at.y - heldV;
      if (heldV && stepsLeft > 0 && y >= 3 && y < shown.water_level && !blockedAt(at.x, y)) {
        at = { x: at.x, y };
        stepsLeft -= 1;
        this.pushEvent("rise", { dir: heldV });
      }
      if (at === start) return;
      predicted = { x: at.x, y: at.y, at: now };
    };
    const floating = () => (myWizard()?.float ?? 0) > 0;
    const moveStep = (now: number) => (floating() ? flyStep(now) : heldDir ? walkStep(now) : undefined);

    // The land carries on past each edge as its own mirror image, so the world's left
    // and right ends don't look cut off; a cave's ceiling carries on above, fading into
    // solid rock.
    let edges: { left: HTMLCanvasElement; right: HTMLCanvasElement; top: HTMLCanvasElement | null } | null = null;
    const buildEdges = () => {
      if (!shown || !terrainCanvas) return;
      const R = terrainRes;
      const n = EDGE_FADE * R;
      const h = shown.height * R;
      const strip = (w: number, hh: number, paint: (c: CanvasRenderingContext2D) => void, fade: (c: CanvasRenderingContext2D) => CanvasGradient) => {
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = hh;
        const c = canvas.getContext("2d")!;
        paint(c);
        c.globalCompositeOperation = "destination-in";
        c.fillStyle = fade(c);
        c.fillRect(0, 0, w, hh);
        return canvas;
      };
      const land = terrainCanvas;
      const mirror = (c: CanvasRenderingContext2D, from: number) => {
        c.translate(n, 0);
        c.scale(-1, 1);
        c.drawImage(land, from, 0, n, h, 0, 0, n, h);
        c.setTransform(1, 0, 0, 1, 0, 0);
      };
      // The mirrored land runs on at full strength, so the edge column meets its own
      // reflection and the ground and sea carry on seamlessly past the dashed line.
      const shore = (side: "left" | "right") => {
        const canvas = document.createElement("canvas");
        canvas.width = n;
        canvas.height = h;
        mirror(canvas.getContext("2d")!, side === "left" ? 0 : land.width - n);
        return canvas;
      };
      const left = shore("left");
      const right = shore("right");
      let top: HTMLCanvasElement | null = null;
      if (ceiling) {
        const rows = 24 * R;
        top = strip(land.width, rows, (c) => {
          c.translate(0, rows);
          c.scale(1, -1);
          c.drawImage(land, 0, 0, land.width, rows, 0, 0, land.width, rows);
        }, (c) => {
          const g = c.createLinearGradient(0, rows, 0, 0);
          g.addColorStop(0, "rgba(0,0,0,1)");
          g.addColorStop(1, "rgba(0,0,0,0)");
          return g;
        });
      }
      edges = { left, right, top };
    };

    const buildLand = () => {
      if (!shown || !cells) return;
      landDirty = false;
      const texture = art.textures[shown.map_id];
      if (ready(texture)) {
        terrainCanvas = paintLand(cells, shown.width, shown.height, texture, palette(), scorches);
        terrainRes = LAND_RES;
      } else {
        terrainCanvas = terrainImage(cells, shown.width, shown.height, palette());
        terrainRes = 1;
      }
      buildEdges();
    };

    const poseOf = (unit: Unit, now: number, moving: boolean, knocked: boolean): Pose => {
      if (!shown) return "idle";
      if (shown.phase === "game_ended") return "win";
      const at = spawnAt(unit.id);
      if (at !== null && now - at < SPAWN_DROP_MS + 950) {
        const el = now - at;
        return el < SPAWN_DROP_MS ? "spawn" : el < SPAWN_DROP_MS + 170 ? "land" : "greet";
      }
      if (knocked) return "tumble";
      if (jumping?.id === unit.id) return "jump";
      if ((unit.float ?? 0) > 0) return "fly";
      if (falls.has(unit.id)) return "drop";
      if (unit.id === shown.viewer_id && now - crouchAt < 300) return "crouch";
      if (now - (hurtAt.get(unit.id) ?? -1e9) < 650) return "hurt";
      if (now - (landedAt.get(unit.id) ?? -1e9) < 170) return "land";
      if (animation && animation.cast.caster_id === unit.id && now < animation.start + 420) return "cast";
      if (moving) return "walk";
      const def = spellDef();
      if (unit.id === shown.viewer_id && canCast() && aim && def && def.input !== "instant") return "aim";
      if (shown.bot_aim && unit.id === shown.current_id) return "aim";
      return "idle";
    };

    // A bot lines up its shot where everyone can see it: the arc grows out from its staff
    // (or a crosshair settles on the spot) before it lets fly.
    let botAimSince = 0;
    let botAimKey = "";
    const botFacing = (unit: Unit) => {
      const a = shown?.bot_aim;
      if (!a) return 1;
      if (a.x !== undefined) return a.x >= unit.x ? 1 : -1;
      return Math.cos(((a.angle ?? 0) * Math.PI) / 180) >= 0 ? 1 : -1;
    };
    const drawBotAim = (t: number) => {
      const a = shown?.bot_aim;
      const bot = shown?.units.find((u) => u.id === shown?.current_id && !u.dead);
      if (!shown || !a || !bot || animation) return;
      const key = JSON.stringify(a);
      if (key !== botAimKey) {
        botAimKey = key;
        botAimSince = t;
      }
      const k = Math.min(1, (t - botAimSince) / 900);
      const s = scale();
      const spell = spellById(a.spell);
      const color = spell?.color ?? "#ef4444";
      if (a.x !== undefined && a.y !== undefined) {
        const r = (1 - k) * 40 + 10;
        ctx.strokeStyle = color;
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.arc(a.x * s, a.y * s, r, 0, Math.PI * 2);
        ctx.moveTo(a.x * s - r - 6, a.y * s);
        ctx.lineTo(a.x * s + r + 6, a.y * s);
        ctx.moveTo(a.x * s, a.y * s - r - 6);
        ctx.lineTo(a.x * s, a.y * s + r + 6);
        ctx.stroke();
        return;
      }
      const p = shown.physics;
      const sp = spell ?? { speed: 1, gravity: 1, wind: 1 };
      const beam = spell?.input === "beam";
      const power = beam ? 100 : (a.power ?? 50) * (0.35 + 0.65 * k);
      const speed = (p.max_speed * sp.speed * Math.max(power, 5)) / 100;
      const rad = ((a.angle ?? 0) * Math.PI) / 180;
      let vx = Math.cos(rad) * speed;
      let vy = -Math.sin(rad) * speed;
      let x = bot.x + 0.5;
      let y = bot.y - 2;
      const steps = beam ? Math.min(spell?.range ?? 30, 30) : 26;
      for (let i = 0; i < steps; i++) {
        vx += shown.wind * p.wind_accel * sp.wind * p.dt;
        vy += p.gravity * sp.gravity * p.dt;
        x += beam ? Math.cos(rad) : vx * p.dt;
        y += beam ? -Math.sin(rad) : vy * p.dt;
        if (solidAt(Math.floor(x), Math.floor(y)) || y >= shown.water_level) break;
        if (i % 3 !== 2) continue;
        ctx.globalAlpha = (1 - i / (steps + 4)) * 0.9;
        ctx.fillStyle = color;
        ctx.strokeStyle = "rgba(17,24,39,0.6)";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(x * s, y * s, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    };

    // A flamingo touching down in the intro: a puff of dust and feathers, a thump, and its
    // name, so everyone knows who is who.
    const land = (unit: Unit, now: number) => {
      spawned.add(unit.id);
      landedAt.set(unit.id, now);
      const s = scale();
      const color = shown?.players[unit.id]?.color ?? "#f9a8d4";
      burst((unit.x + 0.5) * s, (unit.y + 1) * s, "#a8a29e", 10, 60);
      burst((unit.x + 0.5) * s, (unit.y - 2) * s, "#f9a8d4", 8, 50);
      kick(0.03);
      sounds.landed();
      floatText(unit, shown?.players[unit.id]?.name ?? "", color, 24, 11);
    };

    const syncVeil = (now: number) => {
      if (!shown) return;
      const progress = art.need(shown.map_id);
      if (veilFill) veilFill.style.width = `${Math.max(4, progress * 100)}%`;
      if (veilMap !== shown.map_id && (progress >= 1 || now - veilSince > VEIL_MAX_MS)) {
        veilMap = shown.map_id;
        // Every flamingo's coloured sheet is made now, behind the veil, not on its first frame.
        if (ready(art.wizard)) for (const p of Object.values(shown.players)) wizardSheet(art.wizard, p.color);
        if (landDirty) buildLand();
      }
      const lift = veilMap === shown.map_id;
      if (lift !== lifted) {
        lifted = lift;
        veil?.classList.toggle("is-lifted", lifted);
        if (!lifted) veilSince = now;
      }
      if (!lifted) return;
      if (!reported) {
        reported = true;
        this.pushEvent("arena_loaded", {});
      }
      if (shown.phase === "arena_intro" && introAt === null) introAt = now;
    };

    const render = (now: number) => {
      frame++;
      syncVeil(now);
      if (landDirty) buildLand();
      if ((heldDir || heldV) && now >= nextStepAt) moveStep(now);
      // The server has had long enough to confirm the last step; its word stands.
      if (predicted && now - predicted.at > 600) predicted = null;
      const dt = Math.min(64, now - lastTime);
      frameDt = dt;
      lastTime = now;

      ctx.setTransform(pixelScale, 0, 0, pixelScale, 0, 0);
      ctx.save();
      if (now < shakeUntil) {
        const k = Math.min(1, (shakeUntil - now) / 450);
        const amp = shakePower * k * k * 0.75;
        // Slow enough (4 to 7 shakes a second) that 60 frames a second still show it as
        // a shake rather than the view jumping about.
        ctx.translate((Math.sin(now / 42) + Math.sin(now / 29) * 0.6) * amp, (Math.cos(now / 37) + Math.sin(now / 23) * 0.6) * amp);
      } else {
        shakePower = 0;
      }

      // The camera moves first so the backdrop follows this frame's view, not the last.
      moveCamera(now, dt);
      drawBackground(now);
      const zoomPunch = punchAt(now);
      ctx.save();
      ctx.translate(W / 2, H / 2);
      ctx.scale(1 + zoomPunch, 1 + zoomPunch);
      ctx.translate(-W / 2, -H / 2);
      ctx.scale(zoom, zoom);
      ctx.translate(-cam.x * CELL, -cam.y * CELL);

      if (shown && terrainCanvas) {
        ctx.imageSmoothingEnabled = terrainRes > 1;
        if (edges?.top && cam.y < 0) {
          // Rock carries on above the cave: its top rows mirrored, deepening into solid rock.
          const rows = 24;
          const rock = palette().rock[1];
          ctx.fillStyle = `rgb(${rock[0]}, ${rock[1]}, ${rock[2]})`;
          ctx.fillRect(-EDGE_FADE * CELL, (cam.y - 2) * CELL, (shown.width + EDGE_FADE * 2) * CELL, (2 - cam.y) * CELL);
          ctx.drawImage(edges.top, 0, -rows * CELL, shown.width * CELL, rows * CELL);
        }
        if (edges) {
          ctx.drawImage(edges.left, -EDGE_FADE * CELL, 0, EDGE_FADE * CELL, shown.height * CELL);
          ctx.drawImage(edges.right, shown.width * CELL, 0, EDGE_FADE * CELL, shown.height * CELL);
        }
        ctx.drawImage(terrainCanvas, 0, 0, shown.width * CELL, shown.height * CELL);
        ctx.imageSmoothingEnabled = true;
        drawEdgeLines();
        const caster = animation?.cast.caster_id;
        const first = animation?.cast.segments[0]?.path;
        const throwDir = first && first.length > 1 ? Math.sign(first[first.length - 1][0] - first[0][0]) : 0;
        const knocked = knockedPositions(now);
        const tumbling = knockedPositions(now, true);
        const moving = new Set<string>();
        const units = shown.units.map((u) => {
          const at = knocked.get(u.id) ?? jumpPosition(u, now);
          if (at) {
            drawn.set(u.id, [at[0], at[1]]);
            return { ...u, x: at[0], y: at[1], dead: false };
          }
          const target = predicted && u.id === shown!.viewer_id && !u.dead ? { ...u, x: predicted.x, y: predicted.y } : u;
          const from = drawn.get(u.id);
          const to = glide(target, dt);
          if (from && dt > 0) velocity.set(u.id, [(to.x - from[0]) / dt, (to.y - from[1]) / dt]);
          if (Math.abs(to.x - target.x) > 0.03 && !((u.float ?? 0) > 0)) movedAt.set(u.id, now);
          if (now - (movedAt.get(u.id) ?? -1e9) < 140) moving.add(u.id);
          const drop = spawnAt(u.id);
          if (drop !== null && now < drop + SPAWN_DROP_MS) {
            const k = Math.max(0, (now - drop) / SPAWN_DROP_MS);
            return { ...u, ...to, y: to.y - SPAWN_HEIGHT * (1 - k * k) };
          }
          if (drop !== null && !spawned.has(u.id)) land(u, now);
          // A flamingo dropping to its death is drawn alive until it hits the water.
          return { ...u, ...to, dead: u.dead && !fallKO.has(u.id) };
        }).filter((u) => !unspawned(u.id, now));

        drawScars(now);
        drawRunes(now);
        for (const crate of shown.crates) drawCrate(crate, now);

        for (const unit of units) {
          const path = jumping?.id === unit.id ? jumping.path : null;
          // Faces where it aims, else where it is going, else where it last faced.
          const vx = velocity.get(unit.id)?.[0] ?? 0;
          if (moving.has(unit.id)) walked.set(unit.id, (walked.get(unit.id) ?? 0) + Math.abs(vx) * dt);
          const faces = path
            ? Math.sign(path[path.length - 1][0] - path[0][0]) || 1
            : unit.id === shown.viewer_id && facing
              ? facing
              : unit.id === shown.current_id && shown.bot_aim
                ? botFacing(unit)
                : unit.id === caster && throwDir
                  ? throwDir
                  : Math.abs(vx) > 0.0005
                  ? Math.sign(vx)
                  : (faced.get(unit.id) ?? (unit.x < shown.width / 2 ? 1 : -1));
          faced.set(unit.id, faces);
          const flying = !unit.dead && (unit.float ?? 0) > 0;
          if (flying) {
            // Rider and broom bob together and lean into the way they fly.
            const s = scale();
            const px = (unit.x + 0.5) * s;
            const py = (unit.y - 0.5) * s;
            ctx.save();
            ctx.translate(px, py + Math.sin(now / 220) * 1.5);
            ctx.rotate(leanOf(unit.id, faces, dt));
            ctx.translate(-px, -py);
          }
          drawWizard(unit, now, faces, poseOf(unit, now, moving.has(unit.id), tumbling.has(unit.id)));
          if (flying) ctx.restore();
        }
        drawWater(now);
        for (const unit of units) drawLabels(unit);
        drawTurnMarker(now);
        drawAim(now);
        drawBotAim(now);
        if (animation && animation.aftermathAt === null) drawFlight(now);
        drawAftermath(now);
      } else {
        ctx.fillStyle = "#111827";
        ctx.font = "bold 20px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.fillText("Summoning the arena…", W / 2, H / 2);
      }

      drawSmoke(dt);
      drawRings(now);
      drawBooms(now);
      drawParticles(dt);
      drawFloaters(dt);
      ctx.restore();
      drawOffscreenMarkers();
      drawGrand(now);
      drawKnockoutBanner(now);
      ctx.restore();
      syncChargeUi(now);
      rafId = requestAnimationFrame(render);
    };

    rafId = requestAnimationFrame(render);

    // ---- Input ----
    const toCells = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      const s = scale();
      return [
        (((event.clientX - rect.left) / rect.width) * W) / (s * zoom) + cam.x,
        (((event.clientY - rect.top) / rect.height) * H) / (s * zoom) + cam.y,
      ];
    };

    const chargePower = (now: number) => (charge ? Math.min(100, 8 + ((now - charge.start) / CHARGE_MS) * 92) : 0);

    const release = () => {
      if (!charge || !aim) return;
      const power = chargePower(performance.now());
      const spell = charge.spell;
      charge = null;
      if (!canAct()) return;
      castLocked = true;
      lastThrow = Math.round(power);
      thrownUntil = performance.now() + 2500;
      const thrown = document.getElementById("arena-thrown");
      if (thrown) thrown.textContent = `${spellById(spell)?.name ?? "Spell"} thrown at ${lastThrow}% power`;
      throwsSeen += 1;
      store?.setItem(THROWS_KEY, String(throwsSeen));
      this.pushEvent("cast", { spell, angle: Math.round(aim.angle * 10) / 10, power: Math.round(power * 10) / 10 });
    };

    // Drops a charge on purpose, without casting; nothing is spent and the turn goes on.
    const cancel = () => {
      if (!charge) return false;
      const name = spellById(charge.spell)?.name ?? "Spell";
      charge = null;
      thrownUntil = performance.now() + 1500;
      const thrown = document.getElementById("arena-thrown");
      if (thrown) thrown.textContent = `${name} cancelled`;
      return true;
    };

    // Lobbed spells charge; beams fire at once; placed spells conjure where you click.
    const trigger = () => {
      const spell = spellDef();
      const wizard = myWizard();
      if (!canCast() || !aim || !spell || !wizard || spell.input === "instant" || charge) return;
      if (spell.input === "place") {
        const target = placeTarget();
        if (!target || !target.inRange || target.sinks) return;
        castLocked = true;
        this.pushEvent("place", { spell: spell.id, x: Math.round(target.x * 10) / 10, y: Math.round(target.y * 10) / 10 });
      } else if (spell.input === "beam") {
        castLocked = true;
        this.pushEvent("cast", { spell: spell.id, angle: Math.round(aim.angle * 10) / 10, power: 100 });
      } else {
        charge = { start: performance.now(), spell: spell.id };
      }
    };

    const updateAim = (event: PointerEvent) => {
      const wizard = myWizard();
      if (!wizard) return;
      const [x, y] = toCells(event);
      const dx = x - (wizard.x + 0.5);
      const dy = y - (wizard.y - 2);
      aim = { angle: (Math.atan2(-dy, dx) * 180) / Math.PI, power: 0 };
      facing = dx >= 0 ? 1 : -1;
    };

    // Jumps go the way the wizard faces, as in Arcanists. On a broomstick the jump
    // keys fly up and down instead.
    const jump = (kind: "high" | "long") => {
      const wizard = myWizard();
      const now = performance.now();
      if (!shown || !wizard || !canAct() || jumping || falls.has(wizard.id) || now < crouchAt + 90) return;
      // The wizard crouches at once; the server's arc follows a moment later.
      crouchAt = now;
      heldDir = 0;
      if ((wizard.float ?? 0) > 0) this.pushEvent("rise", { dir: kind === "high" ? 1 : -1 });
      else this.pushEvent("jump", { kind, dir: facing || (wizard.x < shown.width / 2 ? 1 : -1) });
    };
    const onJump = (event: Event) => jump((event as CustomEvent<{ kind: "high" | "long" }>).detail.kind);

    let drag: { x: number; y: number; camX: number; camY: number; button: number; moved: boolean } | null = null;
    const onPointerMove = (event: PointerEvent) => {
      // A right press while the left is held arrives as a move (a chord), not a pointerdown.
      if (event.button === 2 && cancel()) return;
      const rect = canvas.getBoundingClientRect();
      if (drag) {
        drag.moved ||= Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 5;
        if (!drag.moved) return;
        const perCell = rect.width / VIEW_W;
        cam.x = drag.camX - (event.clientX - drag.x) / perCell;
        cam.y = drag.camY - (event.clientY - drag.y) / perCell;
        clampCam();
        freeLookUntil = performance.now() + 5000;
        return;
      }
      pointer = { x: ((event.clientX - rect.left) / rect.width) * W, y: ((event.clientY - rect.top) / rect.height) * H };
      edgeArmed = true;
      // Aim follows the mouse while charging too.
      updateAim(event);
      dimNear(event.clientX, event.clientY);
    };
    const onPointerLeave = () => {
      pointer = null;
      undim();
    };
    const onPointerDown = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      const px = ((event.clientX - rect.left) / rect.width) * W;
      const py = ((event.clientY - rect.top) / rect.height) * H;
      // Right-click cancels a charge; otherwise a right click opens the spells, as in
      // Worms, and a right or middle drag pans the view.
      if (event.button === 2 && cancel()) {
        event.preventDefault();
        return;
      }
      if (event.button === 1 || event.button === 2) {
        drag = { x: event.clientX, y: event.clientY, camX: cam.x, camY: cam.y, button: event.button, moved: false };
        event.preventDefault();
        return;
      }
      if (event.button !== 0) return;
      canvas.focus();
      // Clicking the arena puts away the spell panel and menu.
      if (hidePanel("arena-spells") || hidePanel("arena-menu")) return;
      const marker = markers.find((m) => px >= m.x && px <= m.x + m.w && py >= m.y && py <= m.y + m.h);
      if (marker) {
        lookAt(marker.id);
        return;
      }
      // Touch and pen taps arrive without a hover first.
      pointer = { x: px, y: py };
      updateAim(event);
      trigger();
    };
    const onPointerUp = () => {
      if (drag?.button === 2 && !drag.moved && shown?.participation === "active") toggleSpells();
      drag = null;
      release();
    };
    // The wheel (or a pinch) zooms; sideways scrolling on a trackpad pans.
    const onWheel = (event: WheelEvent) => {
      if (!shown) return;
      event.preventDefault();
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
        cam.x += event.deltaX / (canvas.getBoundingClientRect().width / VIEW_W);
        clampCam();
        freeLookUntil = performance.now() + 5000;
        return;
      }
      const step = Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.0015));
      zoomTarget = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, zoomTarget * step));
    };
    const onContextMenu = (event: Event) => {
      event.preventDefault();
      cancel();
    };

    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return;
      const key = event.key.toLowerCase();
      if (key === "f" && !event.metaKey && !event.ctrlKey) {
        toggleFull();
        return;
      }
      // Esc backs out one step at a time: a charge, then whatever is open, then the menu.
      if (key === "escape") {
        event.preventDefault();
        if (cancel()) return;
        if (["arena-spells", "arena-help", "arena-drawer", "arena-menu"].some(hidePanel)) return;
        const menu = panel("arena-menu");
        if (menu) this.js().show(menu, { display: "grid" });
        return;
      }
      if (key === "tab") {
        event.preventDefault();
        if (shown?.participation === "active") toggleSpells();
        return;
      }
      if (key === "h") {
        document.getElementById("arena-help-button")?.click();
        return;
      }
      if (key === "c") {
        freeLookUntil = 0;
        return;
      }
      if (!shown || shown.participation !== "active") return;

      if (key === " ") {
        // A keyboard-focused button keeps Space for itself; after a mouse click
        // the focus is not visible and Space still charges.
        if (target?.closest("button, a") && target.matches(":focus-visible")) return;
        event.preventDefault();
        if (!event.repeat) trigger();
        return;
      }

      if (key === "a" || key === "arrowleft" || key === "d" || key === "arrowright") {
        event.preventDefault();
        const dir = key === "a" || key === "arrowleft" ? -1 : 1;
        if (event.repeat && heldDir === dir) return;
        heldDir = dir;
        facing = dir;
        const now = performance.now();
        if (now >= nextStepAt) moveStep(now);
      } else if (key === "w" || key === "arrowup" || key === "s" || key === "arrowdown") {
        event.preventDefault();
        const up = key === "w" || key === "arrowup";
        // On a broomstick the keys fly up and down for as long as they are held.
        if (floating()) {
          if (event.repeat) return;
          heldV = up ? 1 : -1;
          const now = performance.now();
          if (now >= nextStepAt) moveStep(now);
        } else if (!event.repeat) jump(up ? "high" : "long");
      } else if (/^[0-9-]$/.test(key)) {
        const spell = shown.my_spells[key === "0" ? 9 : key === "-" ? 10 : Number(key) - 1];
        if (spell) this.pushEvent("select_spell", { spell });
      }
    };

    // A cancelled gesture or a lost focus never gets its release, so the
    // charge is dropped rather than left to fire itself at full power.
    const dropCharge = () => {
      charge = null;
      drag = null;
      heldDir = 0;
      heldV = 0;
    };

    const onKeyUp = (event: KeyboardEvent) => {
      if (event.key === " ") release();
      const key = event.key.toLowerCase();
      const dir = key === "a" || key === "arrowleft" ? -1 : key === "d" || key === "arrowright" ? 1 : 0;
      if (dir && dir === heldDir) heldDir = 0;
      const v = key === "w" || key === "arrowup" ? 1 : key === "s" || key === "arrowdown" ? -1 : 0;
      if (v && v === heldV) heldV = 0;
    };

    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointerleave", onPointerLeave);
    canvas.addEventListener("pointercancel", dropCharge);
    canvas.addEventListener("wheel", onWheel, { passive: false });
    canvas.addEventListener("contextmenu", onContextMenu);
    canvas.addEventListener("arena:focus", onFocus);
    canvas.addEventListener("arena:jump", onJump);
    window.addEventListener("blur", dropCharge);
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);

    // Unchanged terrain and the static catalog are left out of later updates.
    let latest: ArenaState | null = null;
    // The first snapshot after a (re)mount is the whole board. A cast it carries
    // already resolved while we were away, so the board is shown as it is rather
    // than replayed over what may now be our turn. A hidden tab draws no frames,
    // so it does the same: casts queued there would all play on coming back.
    this.handleEvent<Partial<ArenaState> & { full?: boolean }>("arena_state", ({ full, ...update }) => {
      latest = { ...latest, ...update } as ArenaState;
      // The client owns the selection and follows the server only when the server
      // moves it, such as off a spell that is now cooling down. Checked on arrival,
      // so a snapshot queued behind a playing cast can't undo a newer pick.
      if (update.selected_spell !== undefined && update.selected_spell !== serverSelected) {
        serverSelected = update.selected_spell;
        selected = update.selected_spell || selected;
      }
      if (full || document.hidden) {
        // A jump that happened while we were away is already over.
        seenJump = latest.last_jump?.n ?? -1;
        jumping = null;
        fallHurt.clear();
        fallKO.clear();
        animation = null;
        pending = null;
        backlog.length = 0;
        charge = null;
        show(latest);
      } else {
        receive(latest);
      }
    });
    // Walking into a slope too steep to climb teaches the jump.
    // A jump with nowhere to go is refused (and costs nothing), with its own hint.
    this.handleEvent<{ jump?: boolean }>("arena_blocked", ({ jump }) => {
      predicted = null;
      heldDir = 0;
      heldV = 0;
      const wizard = myWizard();
      if (!wizard || performance.now() - lastBlockedHint < 2500) return;
      lastBlockedHint = performance.now();
      floatText(wizard, jump ? "No room to jump that way" : "Too steep! W to jump", "#fde68a", 15, 15);
    });
    this.handleEvent("arena_unlock", () => {
      castLocked = false;
    });
    this.handleEvent<{ spell: string }>("arena_select", ({ spell }) => {
      selected = spell;
      // The server now holds this pick too, so its next fallback reads as a move.
      serverSelected = spell;
    });

    this.cleanup = () => {
      cancelAnimationFrame(rafId);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("pointerleave", onPointerLeave);
      canvas.removeEventListener("pointercancel", dropCharge);
      window.removeEventListener("blur", dropCharge);
      canvas.removeEventListener("arena:fullscreen", toggleFull);
      canvas.removeEventListener("arena:spells", toggleSpells);
      canvas.removeEventListener("wheel", onWheel);
      canvas.removeEventListener("contextmenu", onContextMenu);
      canvas.removeEventListener("arena:focus", onFocus);
      canvas.removeEventListener("arena:jump", onJump);
      body.classList.remove("arena-charging", "arena-thrown");
      undim();
      resizeObserver.disconnect();
      stopChargeSound?.();
      sounds.close();
    };
  },

  destroyed(this: SpellArenaHook) {
    this.cleanup?.();
  },
};

export default SpellArena;
