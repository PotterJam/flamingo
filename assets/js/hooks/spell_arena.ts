import { createSpellSounds } from "./spell_sounds";

// Renders the Spellslingers arena: destructible terrain, wizards, minions, crates, aiming,
// and the playback of each cast. The server owns every rule and all physics; this hook
// only draws its snapshots, animates the flight and knockback paths the server computed,
// and turns pointer and keyboard input into commands.

type UnitKind = "wizard" | "thornling" | "imp" | "golem" | "wisp" | "dragon";

type Unit = {
  id: string;
  kind: UnitKind;
  owner: string;
  x: number;
  y: number;
  hp: number;
  max_hp: number;
  dead: boolean;
  ward?: number;
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
  // Grand spells are once-a-duel showpieces; sky spells strike anywhere from above.
  grand?: boolean;
  sky?: boolean;
};

// Spells that outlast their cast, from the server: napalm on the ground, a volcano's
// vent, a thunderhead's strip of sky, and a rising tide.
type Zone = { id: string; kind: "napalm" | "volcano" | "thunderhead" | "tide"; owner: string; x?: number; y?: number; x0?: number; x1?: number; turns: number };

type Segment = { path: [number, number][]; start: number; spell: string; radius: number; hit: boolean };

type Hit = { id: string; at: number; hp: number; ward: number };

type Cast = {
  id: number;
  caster_id: string | null;
  spell: string;
  segments: Segment[];
  // Lightning arcs, each striking at a step of the flight timeline.
  beams: { line: [number, number, number, number]; at: number }[];
  // Each unit struck, at the step it is struck, with the health and ward it is left with.
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
  participation: string;
  map_id: string;
  wind: number;
  width: number;
  height: number;
  water_level: number;
  terrain: string;
  units: Unit[];
  crates: Crate[];
  zones?: Zone[];
  last_cast: Cast | null;
  players: Record<string, { name: string; color: string }>;
  spells: Spell[];
  my_spells: string[];
  selected_spell: string;
  // The latest jump, numbered so each one plays once; its path is in unit cells.
  last_jump: { n: number; id: string; path: [number, number][] } | null;
  physics: { dt: number; gravity: number; max_speed: number; wind_accel: number; playback_speed: number; place_range: number; grand_intro_ms?: number };
};

type Floater = { x: number; y: number; text: string; color: string; size: number; life: number; max: number };

type Particle = { x: number; y: number; vx: number; vy: number; life: number; max: number; color: string; size: number };

type Animation = {
  cast: Cast;
  start: number;
  // Segments that have already burst on impact.
  landed: Set<number>;
  // When the projectiles finished and the post-cast state took over.
  aftermathAt: number | null;
  // Hits not yet shown, soonest first, and arcs already struck.
  hits: Hit[];
  zapped: Set<number>;
  // Knocked-out wizards already shown falling, and when the first one fell.
  koShown: Set<string>;
  koAt: number | null;
};

interface SpellArenaHook {
  el: HTMLCanvasElement;
  pushEvent: (event: string, payload: object) => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
  // LiveView's sticky JS commands, so classes survive server patches.
  js: () => { addClass: (el: HTMLElement, names: string) => void; removeClass: (el: HTMLElement, names: string) => void };
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

const PALETTES: Record<string, Palette> = {
  isles: {
    sky: ["#7dd3fc", "#e0f2fe", "#fef3c7"],
    hills: "#c7d2fe",
    water: "rgba(37, 99, 235, 0.78)",
    grass: [[74, 222, 128], [34, 197, 94], [22, 163, 74]],
    soil: [[180, 120, 70], [161, 98, 52]],
    rock: [[120, 113, 108], [133, 77, 40], [120, 68, 34]],
  },
  flamingo: {
    sky: ["#fbcfe8", "#fce7f3", "#fef9c3"],
    hills: "#f9a8d4",
    water: "rgba(14, 165, 233, 0.75)",
    grass: [[253, 164, 175], [251, 113, 133], [244, 63, 94]],
    soil: [[249, 168, 212], [244, 114, 182]],
    rock: [[236, 72, 153], [219, 39, 119], [190, 24, 93]],
  },
  castles: {
    sky: ["#fb923c", "#fdba74", "#fef3c7"],
    hills: "#c2410c",
    water: "rgba(30, 64, 175, 0.8)",
    grass: [[163, 230, 53], [101, 163, 13], [77, 124, 15]],
    soil: [[168, 162, 158], [156, 148, 140]],
    rock: [[120, 113, 108], [87, 83, 78], [68, 64, 60]],
  },
  cavern: {
    sky: ["#1e1b4b", "#312e81", "#4c1d95"],
    hills: "#2e1065",
    water: "rgba(45, 212, 191, 0.7)",
    grass: [[167, 139, 250], [139, 92, 246], [103, 232, 249]],
    soil: [[88, 80, 130], [76, 68, 115]],
    rock: [[67, 56, 102], [55, 48, 90], [217, 249, 157]],
  },
  archipelago: {
    sky: ["#38bdf8", "#bae6fd", "#ecfeff"],
    hills: "#99f6e4",
    water: "rgba(6, 182, 212, 0.75)",
    grass: [[134, 239, 172], [74, 222, 128], [253, 230, 138]],
    soil: [[253, 224, 71], [250, 204, 21]],
    rock: [[214, 211, 209], [168, 162, 158], [120, 113, 108]],
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
      VIEW_H = H / CELL;
      canvas.width = Math.round(W * k);
      canvas.height = Math.round(H * k);
    };
    const resizeObserver = new ResizeObserver(fitResolution);
    resizeObserver.observe(canvas);

    // Full view fills the browser window; tabs and the address bar stay.
    const page = document.getElementById("spellslingers-game")!;
    const setFull = (on: boolean) => {
      if (on) this.js().addClass(page, "arena-full");
      else this.js().removeClass(page, "arena-full");
    };
    const toggleFull = () => setFull(!page.classList.contains("arena-full"));
    canvas.addEventListener("arena:fullscreen", toggleFull);

    // The overlays drawn over the arena (wizard rail, chronicle, spell dock) stay out of
    // the way: they turn to ghosts while a spell charges and dim when the pointer comes
    // near without touching them. Body classes, so LiveView patches leave them alone.
    const body = document.body;
    const OVERLAYS: [string, string][] = [
      ["rail", "arena-rail"],
      ["ticker", "arena-ticker"],
      ["dock", "arena-controls"],
      ["tuning", "arena-tuning-button"],
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

    // While charging, the turn banner (the top strip in full view) becomes the power meter.
    const meter = document.getElementById("arena-meter");
    const meterName = meter?.querySelector<HTMLElement>("[data-meter-name]");
    const meterFill = meter?.querySelector<HTMLElement>("[data-meter-fill]");
    const meterText = meter?.querySelector<HTMLElement>("[data-meter-text]");
    const meterLast = meter?.querySelector<HTMLElement>("[data-meter-last]");
    const thrown = document.getElementById("arena-thrown");
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
          if (meterName) meterName.textContent = spellById(charge.spell)?.name ?? "";
          if (meterLast) {
            meterLast.hidden = lastThrow === null;
            meterLast.style.left = `${lastThrow ?? 0}%`;
          }
        }
      }
      if (charge && meterFill && meterText) {
        const power = chargePower(now);
        meterFill.style.width = `${power}%`;
        meterText.textContent = power >= 100 ? "MAX" : `${Math.round(power)}%`;
      }
      body.classList.toggle("arena-thrown", now < thrownUntil);
    };

    // A strip showing the whole world, every wizard and the view, in the top corner
    // over the arena (just under the top strip in full view).
    const mini = document.getElementById("arena-minimap") as HTMLCanvasElement | null;
    const miniCtx = mini?.getContext("2d");
    const sky = document.getElementById("arena-sky");

    let shown: ArenaState | null = null;
    // The state the current animation leads to, and states carrying later casts
    // that arrived while it played; each of those plays in turn.
    let pending: ArenaState | null = null;
    const backlog: ArenaState[] = [];
    let terrainCanvas: HTMLCanvasElement | null = null;
    let terrainKey = "";
    let seenCastId = -1;
    let animation: Animation | null = null;
    let particles: Particle[] = [];
    let floaters: Floater[] = [];
    let selected = "ember";
    let serverSelected: string | null = null;
    let aim: { angle: number; power: number } | null = null;
    let castLocked = false;
    let lastWalk = 0;
    // Which way the viewer's wizard faces: the last way it walked or aimed. Jumps go this way.
    let facing = 0;
    let seenJump = -1;
    let jumping: { id: string; path: [number, number][]; start: number } | null = null;
    let lastBlockedHint = 0;
    let frame = 0;
    let shakeUntil = 0;
    let shakePower = 0;
    // A grand spell's moment: when its title card started, and the white flash on impact.
    let grand: { start: number; name: string; color: string } | null = null;
    let flashUntil = 0;
    // Glowing rims a grand blast leaves behind, cooling over a few seconds.
    let scars: { x: number; y: number; r: number; born: number }[] = [];
    const sounds = createSpellSounds(() => (Number.isFinite(window.__soundVolume) ? window.__soundVolume : 100) / 100);
    let stopChargeSound: (() => void) | null = null;

    // The canvas is a 200 x 100 cell window onto a wider world; the camera pans it.
    const CELL = W / 200;
    const VIEW_W = W / CELL;
    let VIEW_H = H / CELL;
    // World rows hidden behind the spell dock at the bottom of the arena. The camera
    // may scroll that far past the world's bottom (into the sea), so the lowest
    // ground can always be brought above the dock.
    let dockPad = 0;
    const measureDock = () => {
      const dock = document.getElementById("arena-controls");
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
    let pointer: { x: number; y: number } | null = null;
    // Lobbed spells charge while the button is held, like a power bar.
    let charge: { start: number; spell: string } | null = null;
    const CHARGE_MS = 1300;
    // Where each unit is drawn. Steps glide toward the server position; jumps of
    // more than a few cells are teleports and flash at both ends.
    const drawn = new Map<string, [number, number]>();
    let cells: Uint8Array | null = null;
    let ceiling = false;
    const solidAt = (x: number, y: number) =>
      !!shown && !!cells && x >= 0 && x < shown.width && y >= 0 && y < shown.height && cells[y * shown.width + x] === 1;

    const clampCam = () => {
      if (!shown) return;
      cam.x = Math.max(0, Math.min(shown.width - VIEW_W, cam.x));
      // A view taller than the world sits on its bottom, with sky or rock above.
      const maxY = shown.height + dockPad - VIEW_H;
      cam.y = Math.max(Math.min(0, maxY), Math.min(maxY, cam.y));
    };
    const palette = () => PALETTES[shown?.map_id ?? "isles"] ?? PALETTES.isles;

    const floatText = (unit: Unit, text: string, color: string, size: number) => {
      const s = scale();
      const max = size > 20 ? 1800 : 1300;
      floaters.push({ x: (unit.x + 0.5) * s, y: (unit.y - 3) * s, text, color, size, life: max, max });
    };

    // Shows how much each unit's health changed between two states, where it stood.
    // One sound per kind of change, at the size of the biggest hit, so a quake hitting
    // everyone is one thump rather than a pile of them.
    // Units in `skip` are left to the cast playing, which shows their knockout itself.
    const announceChanges = (before: ArenaState, after: ArenaState, skip?: Set<string>) => {
      const old = new Map(before.units.map((u) => [u.id, u]));
      let worstHit = 0;
      let healed = false;
      let blocked = false;
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
        else if (delta > 0) floatText(prev, `+${delta}`, "#16a34a", 18);
        if (delta < 0) worstHit = Math.max(worstHit, -delta);
        if (delta > 0) healed = true;
        if ((prev.ward ?? 0) > 0 && (unit.ward ?? 0) < (prev.ward ?? 0) && delta === 0 && !unit.dead) {
          floatText(prev, "blocked", "#3b82f6", 15);
          blocked = true;
        }
      }
      if (worstHit) sounds.hurt(worstHit);
      if (healed) sounds.heal();
      if (blocked) sounds.blocked();
      if (summoned) sounds.summoned();
    };

    const show = (state: ArenaState, skip?: Set<string>) => {
      if (shown && shown.units !== state.units) announceChanges(shown, state, skip);
      const jump = state.last_jump;
      if (jump && jump.n !== seenJump) {
        seenJump = jump.n;
        if (shown) {
          jumping = { id: jump.id, path: jump.path, start: performance.now() };
          sounds.jump();
        }
      }
      const key = state.terrain + state.map_id;
      shown = state;
      // Full view shows open sky above the 2:1 map, in the sky's top colour.
      if (sky) sky.style.background = palette().sky[0];
      if (key !== terrainKey) {
        terrainKey = key;
        cells = decodeTerrain(state.terrain, state.width, state.height);
        // A world whose top row is mostly rock (the cavern) has a ceiling to continue upward.
        let top = 0;
        for (let x = 0; x < state.width; x++) top += cells[x];
        ceiling = top > state.width / 2;
        terrainCanvas = terrainImage(cells, state.width, state.height, palette());
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
          zapped: new Set(),
          koShown: new Set(),
          koAt: null,
        };
        if (cast.grand) {
          const def = spellById(cast.spell);
          grand = { start: at, name: def?.name ?? "Grand spell", color: def?.color ?? "#fb923c" };
        }
        pending = state;
        castLocked = true;
        sounds.cast(cast, (shown.physics.dt * 1000) / shown.physics.playback_speed);
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
      shown.phase === "arena_aim" &&
      shown.current_id === shown.viewer_id &&
      !animation &&
      !castLocked &&
      !jumping &&
      !!myWizard();

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

    const drawWater = (t: number) => {
      if (!shown) return;
      const s = scale();
      const top = shown.water_level * s;
      ctx.fillStyle = palette().water;
      ctx.beginPath();
      const worldW = shown.width * s;
      const bottom = (shown.height + dockPad + 4) * s;
      ctx.moveTo(0, bottom);
      for (let x = 0; x <= worldW; x += 10) ctx.lineTo(x, top + Math.sin(x * 0.04 + t / 400) * 3);
      ctx.lineTo(worldW, bottom);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.6)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (let x = 0; x <= worldW; x += 10) ctx.lineTo(x, top + Math.sin(x * 0.04 + t / 400) * 3);
      ctx.stroke();
    };

    const drawWizard = (unit: Unit, t: number, facing: number) => {
      if (!shown) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const feet = (unit.y + 1) * s;
      const color = shown.players[unit.id]?.color ?? "#9ca3af";

      ctx.lineWidth = 2;
      ctx.strokeStyle = "#111827";

      if (unit.dead) {
        ctx.fillStyle = "#9ca3af";
        ctx.beginPath();
        ctx.roundRect(cx - 6, feet - 14, 12, 14, [6, 6, 0, 0]);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = "#4b5563";
        ctx.fillRect(cx - 1, feet - 11, 2, 7);
        ctx.fillRect(cx - 3.5, feet - 9, 7, 2);
        return;
      }

      const bob = Math.sin(t / 300 + unit.x) * 0.8;

      ctx.strokeStyle = "#78350f";
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.moveTo(cx + facing * 6, feet);
      ctx.lineTo(cx + facing * 8, feet - 17 + bob);
      ctx.stroke();
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(cx + facing * 8, feet - 18 + bob, 2.5, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(cx - 6, feet);
      ctx.lineTo(cx + 6, feet);
      ctx.lineTo(cx + 3, feet - 9 + bob);
      ctx.lineTo(cx - 3, feet - 9 + bob);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = "#fde2c8";
      ctx.beginPath();
      ctx.arc(cx, feet - 11 + bob, 3.6, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = "#111827";
      ctx.fillRect(cx + facing * 1.4 - 0.6, feet - 11.8 + bob, 1.3, 1.3);

      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(cx - 6, feet - 13 + bob);
      ctx.lineTo(cx + 6, feet - 13 + bob);
      ctx.lineTo(cx - facing * 3, feet - 25 + bob);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = "#fde047";
      ctx.beginPath();
      ctx.arc(cx - facing * 0.5, feet - 18 + bob, 1.2, 0, Math.PI * 2);
      ctx.fill();
    };

    const eyes = (cx: number, y: number, color = "#fff") => {
      ctx.fillStyle = color;
      ctx.fillRect(cx - 3, y, 2.2, 2.2);
      ctx.fillRect(cx + 1, y, 2.2, 2.2);
    };

    const drawMinion = (unit: Unit, t: number) => {
      if (!shown) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const feet = (unit.y + 1) * s;
      const wobble = Math.sin(t / 220 + unit.x) * 0.7;
      const owner = shown.players[unit.owner]?.color ?? "#9ca3af";
      ctx.lineWidth = 2;
      ctx.strokeStyle = "#111827";

      let top = feet - 14;

      if (unit.kind === "thornling") {
        ctx.fillStyle = "#16a34a";
        ctx.beginPath();
        for (let i = 0; i < 10; i++) {
          const a = (i / 10) * Math.PI * 2;
          const r = i % 2 === 0 ? 7.5 : 5.2;
          ctx.lineTo(cx + Math.cos(a) * r, feet - 5.5 + wobble + Math.sin(a) * r * 0.85);
        }
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
        eyes(cx, feet - 7 + wobble);
      } else if (unit.kind === "imp") {
        const hop = Math.abs(Math.sin(t / 150 + unit.x)) * 2;
        ctx.fillStyle = "#dc2626";
        ctx.beginPath();
        ctx.ellipse(cx, feet - 5 - hop, 5, 5.5, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(cx - 4, feet - 9 - hop);
        ctx.lineTo(cx - 6, feet - 14 - hop);
        ctx.lineTo(cx - 1.5, feet - 10 - hop);
        ctx.moveTo(cx + 4, feet - 9 - hop);
        ctx.lineTo(cx + 6, feet - 14 - hop);
        ctx.lineTo(cx + 1.5, feet - 10 - hop);
        ctx.fill();
        ctx.stroke();
        eyes(cx, feet - 7 - hop, "#fde047");
        top = feet - 18;
      } else if (unit.kind === "golem") {
        ctx.fillStyle = "#78716c";
        ctx.beginPath();
        ctx.roundRect(cx - 7, feet - 15, 14, 15, 3);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = "#57534e";
        ctx.fillRect(cx - 10, feet - 12, 3, 8);
        ctx.fillRect(cx + 7, feet - 12, 3, 8);
        ctx.strokeStyle = "#44403c";
        ctx.beginPath();
        ctx.moveTo(cx - 3, feet - 4);
        ctx.lineTo(cx + 2, feet - 8);
        ctx.stroke();
        eyes(cx, feet - 12, "#fbbf24");
        top = feet - 19;
      } else if (unit.kind === "dragon") {
        // A purple dragon hovering on beating wings, facing its prey's side of the map.
        const flap = Math.sin(t / 110 + unit.x);
        const bob = Math.sin(t / 300 + unit.x) * 2;
        const face = unit.x < (shown.width ?? 300) / 2 ? 1 : -1;
        const y = feet - 9 + bob;
        ctx.fillStyle = "#a78bfa";
        for (const side of [-1, 1]) {
          ctx.beginPath();
          ctx.moveTo(cx + side * 3, y - 2);
          ctx.lineTo(cx + side * 15, y - 10 - flap * 6);
          ctx.lineTo(cx + side * 10, y + 1);
          ctx.closePath();
          ctx.fill();
          ctx.stroke();
        }
        ctx.fillStyle = "#7c3aed";
        ctx.beginPath();
        ctx.ellipse(cx, y, 8, 5, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(cx - face * 7, y);
        ctx.lineTo(cx - face * 14, y + 4);
        ctx.lineTo(cx - face * 7, y + 3);
        ctx.fill();
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(cx + face * 9, y - 4, 4, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = "#fde047";
        ctx.fillRect(cx + face * 10 - 1, y - 6, 2, 2);
        if (frame % 5 === 0) burst(cx + face * 13, y - 3, "#fb923c", 1, 12);
        top = y - 16;
      } else {
        const float = Math.sin(t / 260 + unit.x) * 2.5;
        ctx.globalAlpha = 0.85;
        ctx.fillStyle = "#cffafe";
        ctx.beginPath();
        ctx.arc(cx, feet - 8 + float, 5, Math.PI, 0);
        ctx.lineTo(cx + 5, feet - 2 + float);
        ctx.lineTo(cx + 2, feet - 4 + float);
        ctx.lineTo(cx, feet - 1 + float);
        ctx.lineTo(cx - 2, feet - 4 + float);
        ctx.lineTo(cx - 5, feet - 2 + float);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
        ctx.globalAlpha = 1;
        eyes(cx, feet - 9 + float, "#0e7490");
        top = feet - 17;
      }

      ctx.fillStyle = owner;
      ctx.beginPath();
      ctx.arc(cx, top + wobble, 2, 0, Math.PI * 2);
      ctx.fill();
    };

    const drawCrate = (crate: Crate, t: number) => {
      const s = scale();
      const cx = (crate.x + 0.5) * s;
      const feet = (crate.y + 1) * s;
      const glow = 0.5 + 0.5 * Math.sin(t / 250 + crate.x);
      ctx.fillStyle = crate.type === "health" ? "#fef2f2" : "#eff6ff";
      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.roundRect(cx - 5, feet - 10, 10, 10, 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = crate.type === "health" ? "#ef4444" : "#3b82f6";
      if (crate.type === "health") {
        ctx.fillRect(cx - 1, feet - 8, 2, 6);
        ctx.fillRect(cx - 3, feet - 6, 6, 2);
      } else {
        ctx.beginPath();
        ctx.moveTo(cx, feet - 9);
        ctx.lineTo(cx + 3, feet - 5);
        ctx.lineTo(cx, feet - 1);
        ctx.lineTo(cx - 3, feet - 5);
        ctx.fill();
      }
      ctx.globalAlpha = glow * 0.5;
      ctx.fillStyle = "#fef08a";
      ctx.beginPath();
      ctx.arc(cx, feet - 16 - glow * 2, 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    };

    // Lasting spells, drawn on the map until they wear off so everyone can play around them.
    const drawZones = (t: number) => {
      if (!shown) return;
      const s = scale();
      for (const zone of shown.zones ?? []) {
        if (zone.kind === "napalm" && zone.x0 !== undefined && zone.x1 !== undefined && zone.y !== undefined) {
          for (let x = zone.x0; x <= zone.x1; x++) {
            const h = 7 + 6 * Math.abs(Math.sin(t / 120 + x * 1.7));
            const base = (zone.y + 1) * s;
            ctx.fillStyle = x % 2 ? "#f97316" : "#facc15";
            ctx.beginPath();
            ctx.moveTo(x * s, base);
            ctx.lineTo((x + 0.5) * s, base - h);
            ctx.lineTo((x + 1) * s, base);
            ctx.fill();
          }
          if (frame % 4 === 0) burst((zone.x0 + Math.random() * (zone.x1 - zone.x0)) * s, (zone.y + 0.5) * s, "#fb923c", 1, 15);
        } else if (zone.kind === "volcano" && zone.x !== undefined && zone.y !== undefined) {
          const glow = 0.5 + 0.3 * Math.sin(t / 150);
          ctx.fillStyle = `rgba(249, 115, 22, ${glow})`;
          ctx.beginPath();
          ctx.arc(zone.x * s, (zone.y + 2) * s, 7, 0, Math.PI * 2);
          ctx.fill();
          if (frame % 3 === 0) burst(zone.x * s, (zone.y + 1) * s, frame % 6 ? "#78716c" : "#f97316", 1, 25);
          turnsBadge(zone.x * s, (zone.y - 4) * s, zone.turns, "#b91c1c");
        } else if (zone.kind === "thunderhead" && zone.x0 !== undefined && zone.x1 !== undefined) {
          const x0 = zone.x0 * s;
          const w = (zone.x1 - zone.x0) * s;
          const top = Math.max(cam.y * s + 30, 30);
          ctx.fillStyle = "rgba(30, 41, 59, 0.12)";
          ctx.fillRect(x0, top, w, shown.water_level * s - top);
          ctx.setLineDash([5, 5]);
          ctx.strokeStyle = "rgba(30, 41, 59, 0.45)";
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.moveTo(x0, top);
          ctx.lineTo(x0, shown.water_level * s);
          ctx.moveTo(x0 + w, top);
          ctx.lineTo(x0 + w, shown.water_level * s);
          ctx.stroke();
          ctx.setLineDash([]);
          const cx = x0 + w / 2 + Math.sin(t / 900) * 3;
          ctx.fillStyle = "#475569";
          ctx.strokeStyle = "#111827";
          ctx.lineWidth = 2.5;
          ctx.beginPath();
          for (const [dx, dy, r] of [[-0.36, 6, 16], [-0.17, -5, 21], [0.05, -8, 23], [0.25, -2, 19], [0.4, 7, 14]]) {
            ctx.moveTo(cx + dx * w + r, top + dy);
            ctx.arc(cx + dx * w, top + dy, r, 0, Math.PI * 2);
          }
          ctx.fill();
          ctx.stroke();
          ctx.fillRect(cx - w * 0.42, top, w * 0.84, 16);
          turnsBadge(cx, top - 2, zone.turns, "#ca8a04");
        }
      }
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

    // How many more turns a lasting spell has, on a coin over it.
    const turnsBadge = (x: number, y: number, turns: number, color: string) => {
      ctx.fillStyle = "#fde047";
      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x, y, 9, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = color;
      ctx.font = "900 11px ui-sans-serif, system-ui";
      ctx.textAlign = "center";
      ctx.fillText(String(turns), x, y + 4);
    };

    const drawAuras = (unit: Unit, t: number) => {
      if (unit.dead) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const feet = (unit.y + 1) * s;

      if ((unit.float ?? 0) > 0) {
        ctx.globalAlpha = 0.5 + 0.2 * Math.sin(t / 200);
        ctx.fillStyle = "#c4b5fd";
        ctx.beginPath();
        ctx.ellipse(cx, feet + 2, 9, 3, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
        if (frame % 6 === 0) burst(cx + (Math.random() - 0.5) * 10, feet + 2, "#ddd6fe", 1, 15);
      }

      if ((unit.ward ?? 0) > 0) {
        const r = unit.kind === "wizard" ? 17 : 12;
        const cy = feet - r * 0.75;
        const glow = ctx.createRadialGradient(cx, cy, r * 0.4, cx, cy, r);
        glow.addColorStop(0, "rgba(147, 197, 253, 0)");
        glow.addColorStop(1, "rgba(96, 165, 250, 0.35)");
        ctx.fillStyle = glow;
        ctx.strokeStyle = `rgba(59, 130, 246, ${0.6 + 0.3 * Math.sin(t / 180)})`;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }
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
      const tall = unit.kind === "wizard" ? 34 : unit.kind === "golem" || unit.kind === "dragon" ? 28 : 22;
      const top = (unit.y + 1) * s - tall;

      if (unit.kind === "wizard") {
        const label = shown.players[unit.id]?.name ?? "?";
        ctx.font = "bold 11px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "white";
        ctx.strokeText(label, cx, top - 6);
        ctx.fillStyle = shown.players[unit.id]?.color ?? "#111827";
        ctx.fillText(label, cx, top - 6);
      }

      const w = unit.kind === "wizard" ? 26 : 16;
      const ratio = unit.hp / unit.max_hp;
      ctx.fillStyle = "#111827";
      ctx.fillRect(cx - w / 2 - 1, top - 2, w + 2, 5);
      ctx.fillStyle = ratio > 0.5 ? "#22c55e" : ratio > 0.25 ? "#f59e0b" : "#ef4444";
      ctx.fillRect(cx - w / 2, top - 1, w * ratio, 3);
    };

    // Where a placed spell would land: open air above the pointer, within range.
    const placeTarget = () => {
      const wizard = myWizard();
      if (!shown || !wizard || !pointer) return null;
      let x = pointer.x / CELL + cam.x;
      let y = pointer.y / CELL + cam.y;
      x = Math.max(0, Math.min(shown.width - 1, x));
      while (y > 1 && solidAt(Math.floor(x), Math.floor(y))) y -= 1;
      const def = spellDef();
      const inRange = !!def?.sky || Math.hypot(x - wizard.x - 0.5, y - wizard.y + 1) <= shown.physics.place_range;
      // Anything but a ledge drops to the ground below; over the sea it is wasted. Of the
      // sky spells only the volcano needs ground under it.
      const drops = def?.sky ? def.effect === "volcano" : def?.effect !== "ledge" && def?.id !== "dragon";
      const sinks = drops && dropTo(x, y) >= shown.water_level - 1;
      return { x, y, inRange, sinks };
    };

    // Where a summon or wall would come to rest: straight down onto the ground.
    const dropTo = (x: number, y: number) => {
      if (!shown) return y;
      let yy = y;
      while (yy < shown.water_level && !solidAt(Math.floor(x), Math.floor(yy + 1))) yy += 1;
      return yy;
    };

    const drawAim = (t: number) => {
      const wizard = myWizard();
      const spell = spellDef();
      if (!shown || !wizard || !aim || !canAct() || !spell || spell.input === "instant") return;
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
        if (spell.effect === "ledge") {
          ctx.fillRect(px - 7.5 * s, py - 0.5 * s, 15 * s, 2 * s);
          ctx.strokeRect(px - 7.5 * s, py - 0.5 * s, 15 * s, 2 * s);
        } else {
          const rest = dropTo(target.x, target.y);
          ctx.setLineDash([3, 4]);
          ctx.beginPath();
          ctx.moveTo(px, py);
          ctx.lineTo(px, rest * s);
          ctx.stroke();
          ctx.setLineDash([]);
          if (spell.effect === "thunderhead") {
            ctx.fillRect(px - 16 * s, py - 40 * s, 32 * s, (rest - py + 40) * s);
          } else if (spell.effect === "cataclysm") {
            ctx.beginPath();
            ctx.arc(px, py, spell.radius * s, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          } else if (spell.effect === "raise") {
            const r = spell.radius * s;
            ctx.fillRect(px - r * 0.45, (rest + 1) * s - r * 1.6, r * 0.9, r * 1.6);
            ctx.strokeRect(px - r * 0.45, (rest + 1) * s - r * 1.6, r * 0.9, r * 1.6);
          } else if (spell.effect === "heal") {
            ctx.beginPath();
            ctx.arc(px, rest * s, spell.radius * s, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          } else {
            ctx.beginPath();
            ctx.ellipse(px, (rest + 1) * s - 9, 7, 9, 0, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          }
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
        ctx.lineTo(ox + dir[0] * 45 * s, oy + dir[1] * 45 * s);
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
      if (spell.input === "charge") {
        const text = charge ? "let go to throw · right-click cancels" : "hold to charge";
        ctx.font = "bold 11px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "white";
        ctx.strokeText(text, ox, oy + 46 + Math.sin(t / 200));
        ctx.fillStyle = "#111827";
        ctx.fillText(text, ox, oy + 46 + Math.sin(t / 200));
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
      const y = (uy + 1) * s - 58 + Math.sin(t / 180) * 4;
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

    const lightning = (x0: number, y0: number, x1: number, y1: number, color: string) => {
      ctx.strokeStyle = color;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      for (let i = 1; i < 8; i++) {
        const k = i / 8;
        ctx.lineTo(x0 + (x1 - x0) * k + (Math.random() - 0.5) * 10, y0 + (y1 - y0) * k + (Math.random() - 0.5) * 10);
      }
      ctx.lineTo(x1, y1);
      ctx.stroke();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1;
      ctx.stroke();
    };

    // Steps elapsed in the server's simulation timeline.
    const castStep = (now: number, since: number, speed = 1) => {
      const p = shown!.physics;
      return ((now - since) / 1000) * (p.playback_speed / p.dt) * speed;
    };

    // Knockouts replay their knockback in slow motion.
    const knockSpeed = (cast: Cast) => (cast.ko?.length ? 0.35 : 1);

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
      const next = {
        ...shown,
        units: shown.units.map((u) => {
          const hit = due.get(u.id);
          return hit ? { ...u, hp: hit.hp, ward: hit.ward } : u;
        }),
      };
      announceChanges(shown, next);
      shown = next;
    };

    // Lightning arcs flash for a moment from the step each one strikes.
    const drawBeams = (now: number) => {
      if (!animation || !shown) return;
      const s = scale();
      const step = castStep(now, animation.start);
      animation.cast.beams.forEach(({ line: [x0, y0, x1, y1], at }, n) => {
        if (step < at || step > at + 20) return;
        if (!animation!.zapped.has(n)) {
          animation!.zapped.add(n);
          sounds.zap();
        }
        lightning(x0 * s, y0 * s, x1 * s, y1 * s, "#93c5fd");
      });
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

          if (segment.spell === "thunderhead") {
            const [sx, sy] = segment.path[0];
            lightning(sx * s, sy * s, x * s, y * s, color);
          } else if (segment.spell === "cataclysm") {
            for (let i = 0; i < 3; i++) burst(x * s + (Math.random() - 0.5) * 20, y * s + (Math.random() - 0.5) * 20, i ? "#fb923c" : "#facc15", 1, 50);
            ctx.fillStyle = "rgba(253, 224, 71, 0.35)";
            ctx.beginPath();
            ctx.arc(x * s, y * s, 30, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = "#7c2d12";
            ctx.strokeStyle = "#111827";
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.arc(x * s, y * s, 16, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            ctx.fillStyle = "#fb923c";
            ctx.beginPath();
            ctx.arc(x * s - 5, y * s + 3, 7, 0, Math.PI * 2);
            ctx.fill();
          } else if (isBeam(segment.spell)) {
            const [tx, ty] = pointAt(segment.path, Math.max(0, local - 4));
            ctx.strokeStyle = color;
            ctx.lineWidth = segment.spell === "gust" ? 7 : 4;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(tx * s, ty * s);
            ctx.lineTo(x * s, y * s);
            ctx.stroke();
            if (segment.spell === "burrow" && frame % 2 === 0) burst(x * s, y * s, "#a16207", 2, 40);
          } else {
            if (frame % 2 === 0) burst(x * s, y * s, color, 1, 20);
            const big = segment.spell === "inferno" ? 8 : segment.spell === "boulder" || segment.spell === "volcano" ? 6 : 4.5;
            ctx.fillStyle = color;
            ctx.strokeStyle = "#111827";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(x * s, y * s, big, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          }
        } else if (!animation!.landed.has(n)) {
          animation!.landed.add(n);
          sounds.land(segment);
          const [x, y] = segment.path[last];
          if (segment.hit && segment.radius > 0 && cast.grand && segment.spell === "cataclysm") {
            // The grand impact: a white flash, a beat of stillness, then the blast and a glowing scar.
            flashUntil = now + 220;
            animation!.start += 140;
            burst(x * s, y * s, "#fff", 40, 320);
            burst(x * s, y * s, "#fde047", 90, 300);
            burst(x * s, y * s, color, 70, 260);
            shake(16, 1000);
            scars.push({ x, y, r: segment.radius + 1, born: now });
          } else if (segment.hit && segment.radius > 0) {
            burst(x * s, y * s, "#fde047", 20 + segment.radius * 4, 100 + segment.radius * 12);
            burst(x * s, y * s, color, 16 + segment.radius * 3, 80 + segment.radius * 10);
            shake(Math.min(8, segment.radius * 0.8), 260);
          } else {
            burst(x * s, y * s, segment.hit ? color : "#bfdbfe", 18, 80);
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
            burst((unit.x + 0.5) * s, (unit.y - 1) * s, colorOf(aura.kind, "#fff"), 26, 70);
          }
        }
        if (pending) {
          show(pending, new Set(cast.ko ?? []));
          pending = null;
          castLocked = true;
        }
      }
    };

    // Where each knocked unit is right now while the aftermath plays.
    const knockedPositions = (now: number) => {
      const positions = new Map<string, [number, number]>();
      if (!animation || animation.aftermathAt === null) return positions;
      const step = castStep(now, animation.aftermathAt, knockSpeed(animation.cast));
      for (const knock of animation.cast.knocks) {
        if (step < knock.path.length - 1) positions.set(knock.id, pointAt(knock.path, step) as [number, number]);
      }
      return positions;
    };

    const drawAftermath = (now: number) => {
      if (!animation || animation.aftermathAt === null || !shown) return;
      const { cast } = animation;
      const elapsed = now - animation.aftermathAt;
      const step = castStep(now, animation.aftermathAt, knockSpeed(cast));

      // A knocked-out wizard falls when their knockback ends, or at once if nothing knocked them.
      let fell = false;
      for (const id of cast.ko ?? []) {
        const knock = cast.knocks.find((k) => k.id === id);
        if (animation.koShown.has(id) || (knock && step < knock.path.length - 1)) continue;
        animation.koShown.add(id);
        animation.koAt ??= now;
        const unit = shown.units.find((u) => u.id === id);
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
        (animation.koAt !== null ? now - animation.koAt > 1300 : elapsed > (cast.beams.length ? 500 : 250));

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
      for (const p of particles) {
        p.vy += 220 * (dt / 1000);
        p.x += p.vx * (dt / 1000);
        p.y += p.vy * (dt / 1000);
        ctx.globalAlpha = Math.max(0, p.life / p.max);
        ctx.fillStyle = p.color;
        ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
      }
      ctx.globalAlpha = 1;
    };

    // What the camera should look at: the flying spell, then whoever got knocked,
    // then the wizard whose turn it is. Free look pauses following between casts.
    const cameraFocus = (now: number): [number, number] | null => {
      if (!shown) return null;
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
        const knocked = [...knockedPositions(now).values()];
        if (knocked.length) return knocked[0];
      }
      if (now < freeLookUntil && !animation) return null;
      const unit = shown.units.find((u) => u.id === shown!.current_id && !u.dead);
      return unit ? [unit.x + 0.5, unit.y - 4] : null;
    };

    const moveCamera = (now: number, dt: number) => {
      if (!shown) return;
      dockPad = measureDock();
      // Pointer at the left or right edge pans the view, Worms style.
      if (pointer && !charge && !animation) {
        const edge = 40;
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
          const k = 1 - Math.exp(-dt / (animation ? 140 : 260));
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
      const s = scale();
      burst((unit.x + 0.5) * s, (unit.y + 1) * s, "#a8a29e", 10, 50);
      sounds.landed();
      return null;
    };

    const glide = (unit: Unit, dt: number) => {
      const s = scale();
      const prev = drawn.get(unit.id);
      if (!prev || unit.dead) {
        drawn.set(unit.id, [unit.x, unit.y]);
        return { x: unit.x, y: unit.y };
      }
      if (Math.hypot(unit.x - prev[0], unit.y - prev[1]) > 6) {
        sounds.teleport();
        const color = colorOf("blink", "#c084fc");
        burst((prev[0] + 0.5) * s, (prev[1] - 1) * s, color, 30, 90);
        burst((unit.x + 0.5) * s, (unit.y - 1) * s, color, 40, 120);
        burst((unit.x + 0.5) * s, (unit.y - 1) * s, "#fff", 16, 60);
        drawn.set(unit.id, [unit.x, unit.y]);
        return { x: unit.x, y: unit.y };
      }
      const k = 1 - Math.exp(-dt / 55);
      const x = prev[0] + (unit.x - prev[0]) * k;
      const y = prev[1] + (unit.y - prev[1]) * k;
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

    // The minimap is its own canvas over the arena, so in full view it can sit under the
    // top strip rather than wherever the 2:1 map happens to start.
    const drawMinimap = () => {
      if (!shown || !terrainCanvas || !mini || !miniCtx) return;
      const w = mini.clientWidth;
      const h = (w * shown.height) / shown.width;
      const dpr = window.devicePixelRatio || 1;
      if (mini.width !== Math.round(w * dpr) || mini.height !== Math.round(h * dpr)) {
        mini.width = Math.round(w * dpr);
        mini.height = Math.round(h * dpr);
      }
      const c = miniCtx;
      const k = w / shown.width;
      c.setTransform(dpr, 0, 0, dpr, 0, 0);
      c.clearRect(0, 0, w, h);
      c.globalAlpha = 0.9;
      c.fillStyle = "rgba(15, 23, 42, 0.55)";
      c.fillRect(0, 0, w, h);
      c.imageSmoothingEnabled = false;
      c.drawImage(terrainCanvas, 0, 0, w, h);
      c.fillStyle = palette().water;
      c.fillRect(0, shown.water_level * k, w, h - shown.water_level * k);
      for (const unit of shown.units) {
        if (unit.dead || unit.kind !== "wizard") continue;
        c.fillStyle = shown.players[unit.id]?.color ?? "#fff";
        c.strokeStyle = "#111827";
        c.lineWidth = 1;
        c.beginPath();
        c.arc((unit.x + 0.5) * k, (unit.y - 1) * k, unit.id === shown.current_id ? 3.5 : 2.5, 0, Math.PI * 2);
        c.fill();
        c.stroke();
      }
      c.globalAlpha = 1;
      c.strokeStyle = "#fff";
      c.lineWidth = 1.5;
      c.strokeRect(cam.x * k, cam.y * k, VIEW_W * k, VIEW_H * k);
      c.strokeStyle = "#111827";
      c.lineWidth = 2;
      c.strokeRect(1, 1, w - 2, h - 2);
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
        if (unit.dead || unit.kind !== "wizard") continue;
        const sx = (unit.x + 0.5 - cam.x) * CELL;
        if (sx >= 0 && sx <= W) {
          visible.push({ x: sx, top: (unit.y - 4 - cam.y) * CELL - 28, bottom: (unit.y + 1 - cam.y) * CELL });
          continue;
        }
        sides[sx < 0 ? "left" : "right"].push({ unit, y: Math.max(24, Math.min(H - 24, (unit.y - 1 - cam.y) * CELL)) });
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
    const onFocus = (event: Event) => lookAt((event as CustomEvent<{ id: string }>).detail?.id);

    // Where the viewer's wizard is on screen, for the first-turn tour to point at.
    (canvas as HTMLCanvasElement & { viewerPoint?: () => { x: number; y: number; k: number } | null }).viewerPoint = () => {
      const unit = myWizard();
      if (!unit) return null;
      const r = canvas.getBoundingClientRect();
      const k = (r.width / W) * CELL;
      const [x, y] = drawn.get(unit.id) ?? [unit.x, unit.y];
      return { x: r.left + (x + 0.5 - cam.x) * k, y: r.top + (y - cam.y) * k, k };
    };

    const minimapJump = (event: PointerEvent) => {
      if (!shown || !mini || event.button !== 0) return;
      const r = mini.getBoundingClientRect();
      const k = r.width / shown.width;
      cam.x = (event.clientX - r.left) / k - VIEW_W / 2;
      cam.y = (event.clientY - r.top) / k - VIEW_H / 2;
      clampCam();
      freeLookUntil = performance.now() + 4000;
    };

    let lastTime = performance.now();
    let rafId = 0;

    const render = (now: number) => {
      frame++;
      const dt = Math.min(64, now - lastTime);
      lastTime = now;

      ctx.setTransform(pixelScale, 0, 0, pixelScale, 0, 0);
      ctx.save();
      if (now < shakeUntil) {
        const k = (shakeUntil - now) / 700;
        ctx.translate((Math.random() - 0.5) * shakePower * 2 * k, (Math.random() - 0.5) * shakePower * 2 * k);
      } else {
        shakePower = 0;
      }

      drawBackground(now);
      moveCamera(now, dt);
      ctx.save();
      ctx.translate(-cam.x * CELL, -cam.y * CELL);

      if (shown && terrainCanvas) {
        ctx.imageSmoothingEnabled = false;
        if (ceiling && cam.y < 0) {
          // Rock carries on above the world: its top rows mirrored, then solid rock.
          const rows = 24;
          const rock = palette().rock[0];
          ctx.fillStyle = `rgb(${rock[0]}, ${rock[1]}, ${rock[2]})`;
          ctx.fillRect(0, (cam.y - 1) * CELL, shown.width * CELL, (-cam.y - rows + 1) * CELL);
          ctx.save();
          ctx.scale(1, -1);
          ctx.drawImage(terrainCanvas, 0, 0, shown.width, rows, 0, 0, shown.width * CELL, rows * CELL);
          ctx.restore();
        }
        ctx.drawImage(terrainCanvas, 0, 0, shown.width * CELL, shown.height * CELL);
        const caster = animation?.cast.caster_id;
        const knocked = knockedPositions(now);
        const units = shown.units.map((u) => {
          const at = knocked.get(u.id) ?? jumpPosition(u, now);
          if (at) {
            drawn.set(u.id, [at[0], at[1]]);
            return { ...u, x: at[0], y: at[1], dead: false };
          }
          return { ...u, ...glide(u, dt) };
        });

        drawZones(now);
        for (const crate of shown.crates) drawCrate(crate, now);

        for (const unit of units) {
          if (unit.kind === "wizard") {
            const path = jumping?.id === unit.id ? jumping.path : null;
            const faces = path
              ? Math.sign(path[path.length - 1][0] - path[0][0]) || 1
              : unit.id === shown.viewer_id && facing
                ? facing
                : unit.id === caster ? 1 : unit.x < shown.width / 2 ? 1 : -1;
            drawWizard(unit, now, faces);
          } else {
            drawMinion(unit, now);
          }
        }
        for (const unit of units) drawAuras(unit, now);
        drawWater(now);
        for (const unit of units) drawLabels(unit);
        drawTurnMarker(now);
        drawAim(now);
        if (animation && animation.aftermathAt === null) drawFlight(now);
        drawBeams(now);
        drawAftermath(now);
      } else {
        ctx.fillStyle = "#111827";
        ctx.font = "bold 20px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.fillText("Summoning the arena…", W / 2, H / 2);
      }

      drawParticles(dt);
      drawFloaters(dt);
      ctx.restore();
      drawOffscreenMarkers();
      drawGrand(now);
      drawKnockoutBanner(now);
      ctx.restore();
      drawMinimap();
      syncChargeUi(now);
      rafId = requestAnimationFrame(render);
    };

    rafId = requestAnimationFrame(render);

    // ---- Input ----
    const toCells = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      const s = scale();
      return [
        (((event.clientX - rect.left) / rect.width) * W) / s + cam.x,
        (((event.clientY - rect.top) / rect.height) * H) / s + cam.y,
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
      if (thrown) thrown.textContent = `${spellById(spell)?.name ?? "Spell"} thrown at ${lastThrow}% power`;
      this.pushEvent("cast", { spell, angle: Math.round(aim.angle * 10) / 10, power: Math.round(power * 10) / 10 });
    };

    // Drops a charge on purpose, without casting; nothing is spent and the turn goes on.
    const cancel = () => {
      if (!charge) return false;
      const name = spellById(charge.spell)?.name ?? "Spell";
      charge = null;
      thrownUntil = performance.now() + 1500;
      if (thrown) thrown.textContent = `${name} cancelled`;
      return true;
    };

    // Lobbed spells charge; beams fire at once; placed spells conjure where you click.
    const trigger = () => {
      const spell = spellDef();
      const wizard = myWizard();
      if (!canAct() || !aim || !spell || !wizard || spell.input === "instant" || charge) return;
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

    // Jumps go the way the wizard faces, as in Arcanists. While levitating, the jump
    // keys float up and down instead.
    const jump = (kind: "high" | "long") => {
      const wizard = myWizard();
      if (!shown || !wizard || !canAct() || performance.now() - lastWalk < 85) return;
      lastWalk = performance.now();
      if ((wizard.float ?? 0) > 0) this.pushEvent("rise", { dir: kind === "high" ? 1 : -1 });
      else this.pushEvent("jump", { kind, dir: facing || (wizard.x < shown.width / 2 ? 1 : -1) });
    };
    const onJump = (event: Event) => jump((event as CustomEvent<{ kind: "high" | "long" }>).detail.kind);

    let drag: { x: number; y: number; camX: number; camY: number } | null = null;
    const onPointerMove = (event: PointerEvent) => {
      // A right press while the left is held arrives as a move (a chord), not a pointerdown.
      if (event.button === 2 && cancel()) return;
      const rect = canvas.getBoundingClientRect();
      if (drag) {
        const perCell = rect.width / VIEW_W;
        cam.x = drag.camX - (event.clientX - drag.x) / perCell;
        cam.y = drag.camY - (event.clientY - drag.y) / perCell;
        clampCam();
        freeLookUntil = performance.now() + 5000;
        return;
      }
      pointer = { x: ((event.clientX - rect.left) / rect.width) * W, y: ((event.clientY - rect.top) / rect.height) * H };
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
      // Right-click cancels a charge; otherwise right or middle drag pans the view.
      if (event.button === 2 && cancel()) {
        event.preventDefault();
        return;
      }
      if (event.button === 1 || event.button === 2) {
        drag = { x: event.clientX, y: event.clientY, camX: cam.x, camY: cam.y };
        event.preventDefault();
        return;
      }
      if (event.button !== 0) return;
      canvas.focus();
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
      drag = null;
      release();
    };
    // Scrolling (a wheel, or two fingers on a trackpad) pans the view too.
    const onWheel = (event: WheelEvent) => {
      if (!shown || event.ctrlKey) return;
      event.preventDefault();
      const perCell = canvas.getBoundingClientRect().width / VIEW_W;
      const dx = event.shiftKey ? event.deltaY : event.deltaX;
      const dy = event.shiftKey ? 0 : event.deltaY;
      cam.x += dx / perCell;
      cam.y += dy / perCell;
      clampCam();
      freeLookUntil = performance.now() + 5000;
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
      if (key === "escape" && cancel()) return;
      if (key === "escape" && page.classList.contains("arena-full")) {
        setFull(false);
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
        if (!canAct() || performance.now() - lastWalk < 85) return;
        lastWalk = performance.now();
        facing = key === "a" || key === "arrowleft" ? -1 : 1;
        this.pushEvent("walk", { dir: facing });
      } else if (key === "w" || key === "arrowup" || key === "s" || key === "arrowdown") {
        event.preventDefault();
        if (!event.repeat) jump(key === "w" || key === "arrowup" ? "high" : "long");
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
    };

    const onKeyUp = (event: KeyboardEvent) => {
      if (event.key === " ") release();
    };

    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointerleave", onPointerLeave);
    canvas.addEventListener("pointercancel", dropCharge);
    mini?.addEventListener("pointerdown", minimapJump);
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
    // than replayed over what may now be our turn.
    this.handleEvent<Partial<ArenaState> & { full?: boolean }>("arena_state", ({ full, ...update }) => {
      latest = { ...latest, ...update } as ArenaState;
      // The client owns the selection and follows the server only when the server
      // moves it, such as off a spell that is now cooling down. Checked on arrival,
      // so a snapshot queued behind a playing cast can't undo a newer pick.
      if (update.selected_spell !== undefined && update.selected_spell !== serverSelected) {
        serverSelected = update.selected_spell;
        selected = update.selected_spell || selected;
      }
      if (full) {
        // A jump that happened while we were away is already over.
        seenJump = latest.last_jump?.n ?? -1;
        jumping = null;
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
    this.handleEvent("arena_blocked", () => {
      const wizard = myWizard();
      if (!wizard || performance.now() - lastBlockedHint < 2500) return;
      lastBlockedHint = performance.now();
      floatText(wizard, "Too steep! W to jump", "#111827", 15);
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
      mini?.removeEventListener("pointerdown", minimapJump);
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
