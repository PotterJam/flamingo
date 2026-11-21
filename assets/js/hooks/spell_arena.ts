// Renders the Spellslingers arena: destructible terrain, wizards, minions, crates, aiming,
// and the playback of each cast. The server owns every rule and all physics; this hook
// only draws its snapshots, animates the flight and knockback paths the server computed,
// and turns pointer and keyboard input into commands.

type UnitKind = "wizard" | "thornling" | "imp" | "golem" | "wisp";

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
  quick: boolean;
  place: boolean;
};

type Segment = { path: [number, number][]; start: number; spell: string; radius: number; hit: boolean };

type Cast = {
  id: number;
  caster_id: string | null;
  spell: string;
  segments: Segment[];
  beams: [number, number, number, number][];
  knocks: { id: string; path: [number, number][] }[];
  shake: boolean;
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
  last_cast: Cast | null;
  players: Record<string, { name: string; color: string }>;
  spells: Spell[];
  my_spells: string[];
  selected_spell: string;
  physics: { dt: number; gravity: number; max_speed: number; wind_accel: number; playback_speed: number; place_range: number };
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
};

interface SpellArenaHook {
  el: HTMLCanvasElement;
  pushEvent: (event: string, payload: object) => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
  // LiveView's sticky JS commands, so classes survive server patches.
  js: () => { addClass: (el: HTMLElement, names: string) => void; removeClass: (el: HTMLElement, names: string) => void };
  cleanup?: () => void;
}

const SPELL_COLORS: Record<string, string> = {
  ember: "#f97316",
  blink: "#c084fc",
  cluster: "#ef4444",
  inferno: "#facc15",
  firerain: "#fb923c",
  imp: "#dc2626",
  boulder: "#78716c",
  rampart: "#a16207",
  golem: "#57534e",
  quake: "#92400e",
  lance: "#fde047",
  gust: "#e0f2fe",
  chain: "#93c5fd",
  wisp: "#a5f3fc",
  thornling: "#22c55e",
  bloom: "#f472b6",
  burrow: "#d97706",
  chaos: "#d946ef",
  ward: "#60a5fa",
  levitate: "#c4b5fd",
  ledge: "#a8a29e",
  updraft: "#7dd3fc",
  swap: "#f0abfc",
  surge: "#f43f5e",
};

const BEAM_SPELLS = new Set(["lance", "chain", "burrow", "gust"]);

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
    const W = canvas.width;
    const H = canvas.height;
    let pixelScale = 1;
    const fitResolution = () => {
      const k = Math.min(4, Math.max(1, (canvas.clientWidth * window.devicePixelRatio) / W));
      if (Math.abs(k - pixelScale) < 0.05) return;
      pixelScale = k;
      canvas.width = Math.round(W * k);
      canvas.height = Math.round(H * k);
    };
    const resizeObserver = new ResizeObserver(fitResolution);
    resizeObserver.observe(canvas);

    // Full screen: the class makes the page fill the window even where the
    // Fullscreen API is missing (iPhone Safari), and the API hides browser chrome.
    const page = document.getElementById("spellslingers-game")!;
    const setFull = (on: boolean) => {
      if (on) this.js().addClass(page, "arena-full");
      else this.js().removeClass(page, "arena-full");
    };
    const toggleFull = () => {
      if (!page.classList.contains("arena-full")) {
        setFull(true);
        page.requestFullscreen?.().catch(() => {});
      } else {
        setFull(false);
        if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
      }
    };
    const onFullscreenChange = () => {
      if (!document.fullscreenElement && page.classList.contains("arena-full")) setFull(false);
    };
    canvas.addEventListener("arena:fullscreen", toggleFull);
    document.addEventListener("fullscreenchange", onFullscreenChange);

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
    let aim: { angle: number; power: number } | null = null;
    let castLocked = false;
    let lastWalk = 0;
    let frame = 0;
    let shakeUntil = 0;
    let shakePower = 0;
    let audio: AudioContext | null = null;

    // The canvas is a 200 x 100 cell window onto a wider world; the camera pans it.
    const CELL = W / 200;
    const VIEW_W = W / CELL;
    const VIEW_H = H / CELL;
    const scale = () => CELL;
    const cam = { x: 0, y: 0 };
    let camReady = false;
    // Free look: the player panned by hand, so the camera stops following for a while.
    let freeLookUntil = 0;
    let pointer: { x: number; y: number } | null = null;
    // Lobbed spells charge while the button is held, like a power bar.
    let charge: { start: number } | null = null;
    const CHARGE_MS = 1300;
    // Where each unit is drawn. Steps glide toward the server position; jumps of
    // more than a few cells are teleports and flash at both ends.
    const drawn = new Map<string, [number, number]>();
    let cells: Uint8Array | null = null;
    const solidAt = (x: number, y: number) =>
      !!shown && !!cells && x >= 0 && x < shown.width && y >= 0 && y < shown.height && cells[y * shown.width + x] === 1;

    const clampCam = () => {
      if (!shown) return;
      cam.x = Math.max(0, Math.min(shown.width - VIEW_W, cam.x));
      cam.y = Math.max(0, Math.min(shown.height - VIEW_H, cam.y));
    };
    const palette = () => PALETTES[shown?.map_id ?? "isles"] ?? PALETTES.isles;

    const floatText = (unit: Unit, text: string, color: string, size: number) => {
      const s = scale();
      const max = size > 20 ? 1800 : 1300;
      floaters.push({ x: (unit.x + 0.5) * s, y: (unit.y - 3) * s, text, color, size, life: max, max });
    };

    // Shows how much each unit's health changed between two states, where it stood.
    const announceChanges = (before: ArenaState, after: ArenaState) => {
      const old = new Map(before.units.map((u) => [u.id, u]));
      for (const unit of after.units) {
        const prev = old.get(unit.id);
        if (!prev) continue;
        const delta = unit.hp - prev.hp;
        if (unit.dead && !prev.dead) floatText(prev, "KO!", "#dc2626", 30);
        else if (delta < 0) floatText(prev, `${delta}`, "#ef4444", delta <= -30 ? 24 : 18);
        else if (delta > 0) floatText(prev, `+${delta}`, "#16a34a", 18);
        if ((prev.ward ?? 0) > 0 && (unit.ward ?? 0) < (prev.ward ?? 0) && delta === 0 && !unit.dead)
          floatText(prev, "blocked", "#3b82f6", 15);
      }
    };

    const show = (state: ArenaState) => {
      if (shown && shown.units !== state.units) announceChanges(shown, state);
      const key = state.terrain + state.map_id;
      shown = state;
      selected = state.selected_spell || selected;
      if (key !== terrainKey) {
        terrainKey = key;
        cells = decodeTerrain(state.terrain, state.width, state.height);
        terrainCanvas = terrainImage(cells, state.width, state.height, palette());
      }
      if (state.last_cast) seenCastId = state.last_cast.id;
      castLocked = false;
    };

    const receive = (state: ArenaState) => {
      const cast = state.last_cast;

      if (animation) {
        if (cast?.id === animation.cast.id) pending = state;
        else backlog.push(state);
      } else if (shown && cast && cast.id !== seenCastId) {
        seenCastId = cast.id;
        animation = { cast, start: performance.now(), landed: new Set(), aftermathAt: null };
        pending = state;
        castLocked = true;
        playWhoosh(cast.spell);
      } else {
        show(state);
      }
    };

    // ---- Sound: tiny synthesized effects, scaled by the site-wide volume ----
    const volume = () => (Number.isFinite(window.__soundVolume) ? window.__soundVolume : 100) / 100;

    const noise = (duration: number, filterFrom: number, filterTo: number, gain: number) => {
      if (volume() === 0) return;
      audio = audio || new AudioContext();
      const now = audio.currentTime;
      const buffer = audio.createBuffer(1, Math.floor(audio.sampleRate * duration), audio.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length) ** 2;
      const source = audio.createBufferSource();
      source.buffer = buffer;
      const filter = audio.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.setValueAtTime(filterFrom, now);
      filter.frequency.exponentialRampToValueAtTime(filterTo, now + duration);
      const amp = audio.createGain();
      amp.gain.value = gain * volume();
      source.connect(filter).connect(amp).connect(audio.destination);
      source.start();
    };

    const playWhoosh = (spell: string) => noise(0.5, BEAM_SPELLS.has(spell) ? 6000 : 2500, 300, 0.22);
    const playBoom = (radius: number) => noise(0.35 + radius * 0.05, 900, 60, 0.5);

    // ---- Physics mirror, used only for the aiming preview ----
    const spellDef = () => shown?.spells.find((s) => s.id === selected);

    const myWizard = () => shown?.units.find((u) => u.kind === "wizard" && u.id === shown?.viewer_id && !u.dead);

    const canAct = () =>
      !!shown && shown.phase === "arena_aim" && shown.current_id === shown.viewer_id && !animation && !castLocked && !!myWizard();

    const previewPath = (power: number) => {
      const wizard = myWizard();
      const spell = spellDef();
      if (!shown || !wizard || !spell || !aim || spell.quick) return [];
      const p = shown.physics;
      const speed = (p.max_speed * spell.speed * Math.max(power, 5)) / 100;
      const rad = (aim.angle * Math.PI) / 180;
      const vx = Math.cos(rad) * speed;
      let vy = -Math.sin(rad) * speed;
      let x = wizard.x + 0.5;
      let y = wizard.y - 2;
      const points: [number, number][] = [];
      for (let i = 0; i < 7; i++) {
        vy += p.gravity * spell.gravity * p.dt;
        x += vx * p.dt;
        y += vy * p.dt;
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
      ctx.moveTo(0, H * 0.62);
      for (let x = 0; x <= W; x += 40) ctx.lineTo(x, H * 0.5 + Math.sin(x * 0.011) * 40 + Math.sin(x * 0.031) * 14);
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
      ctx.moveTo(0, shown.height * s);
      const worldW = shown.width * s;
      const bottom = shown.height * s;
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
      const tall = unit.kind === "wizard" ? 34 : unit.kind === "golem" ? 26 : 22;
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
      const inRange = Math.hypot(x - wizard.x - 0.5, y - wizard.y + 1) <= shown.physics.place_range;
      // Anything but a ledge drops to the ground below; over the sea it is wasted.
      const sinks = spellDef()?.effect !== "ledge" && dropTo(x, y) >= shown.water_level - 1;
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
      if (!shown || !wizard || !aim || !canAct() || !spell || spell.quick) return;
      const s = scale();
      const color = SPELL_COLORS[selected] ?? "#111827";
      const ox = (wizard.x + 0.5) * s;
      const oy = (wizard.y - 2) * s;

      if (spell.place) {
        const target = placeTarget();
        if (!target) return;
        const ok = target.inRange && !target.sinks;
        ctx.save();
        ctx.setLineDash([6, 6]);
        ctx.lineDashOffset = -t / 40;
        ctx.strokeStyle = "rgba(17,24,39,0.35)";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(ox, (wizard.y - 1) * s, shown.physics.place_range * s, 0, Math.PI * 2);
        ctx.stroke();
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
          if (spell.effect === "raise") {
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

      if (spell.gravity === 0) {
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
        // A short stub of the arc: enough to read the angle, not the landing spot.
        const power = charge ? chargePower(t) : 45;
        previewPath(power).forEach(([x, y], i, all) => {
          ctx.globalAlpha = (1 - i / all.length) * (charge ? 1 : 0.6);
          ctx.fillStyle = color;
          ctx.strokeStyle = "rgba(17,24,39,0.5)";
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(x * s, y * s, 3, 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
        });
        ctx.globalAlpha = 1;
      }

      // Crosshair a fixed distance out along the aim.
      const cx = ox + dir[0] * 16 * s;
      const cy = oy + dir[1] * 16 * s;
      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(cx, cy, 6, 0, Math.PI * 2);
      ctx.moveTo(cx - 10, cy);
      ctx.lineTo(cx - 3, cy);
      ctx.moveTo(cx + 3, cy);
      ctx.lineTo(cx + 10, cy);
      ctx.moveTo(cx, cy - 10);
      ctx.lineTo(cx, cy - 3);
      ctx.moveTo(cx, cy + 3);
      ctx.lineTo(cx, cy + 10);
      ctx.stroke();

      // Power bar: a wedge that fills from the wizard while the button is held.
      if (charge) {
        const power = chargePower(t);
        const len = 6 + (power / 100) * 22;
        for (let i = 0; i < len; i += 1.5) {
          const k = i / 28;
          ctx.fillStyle = `hsl(${120 - k * 120}, 90%, 50%)`;
          ctx.beginPath();
          ctx.arc(ox + dir[0] * (2 + i) * s, oy + dir[1] * (2 + i) * s, 1.5 + k * 4, 0, Math.PI * 2);
          ctx.fill();
        }
        if (power >= 100) release();
      } else if (spell.gravity !== 0) {
        ctx.font = "bold 11px ui-sans-serif, system-ui";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.strokeStyle = "white";
        ctx.strokeText("hold to charge", ox, oy + 46 + Math.sin(t / 200));
        ctx.fillStyle = "#111827";
        ctx.fillText("hold to charge", ox, oy + 46 + Math.sin(t / 200));
      }
    };

    const drawTurnMarker = (t: number) => {
      if (!shown || animation || shown.phase !== "arena_aim") return;
      const unit = shown.units.find((u) => u.id === shown!.current_id);
      if (!unit) return;
      const s = scale();
      const cx = (unit.x + 0.5) * s;
      const y = (unit.y + 1) * s - 58 + Math.sin(t / 180) * 4;
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

    const drawFlight = (now: number) => {
      if (!animation || !shown) return;
      const { cast } = animation;
      const s = scale();
      const step = castStep(now, animation.start);

      cast.segments.forEach((segment, n) => {
        const local = step - segment.start;
        const last = segment.path.length - 1;
        const color = SPELL_COLORS[segment.spell] ?? "#f97316";
        if (local < 0) return;

        if (local < last) {
          const [x, y] = pointAt(segment.path, local);

          if (BEAM_SPELLS.has(segment.spell)) {
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
            const big = segment.spell === "inferno" ? 8 : segment.spell === "boulder" ? 6 : 4.5;
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
          const [x, y] = segment.path[last];
          if (segment.hit && segment.radius > 0) {
            burst(x * s, y * s, "#fde047", 20 + segment.radius * 4, 100 + segment.radius * 12);
            burst(x * s, y * s, color, 16 + segment.radius * 3, 80 + segment.radius * 10);
            playBoom(segment.radius);
            shake(Math.min(8, segment.radius * 0.8), 260);
          } else {
            burst(x * s, y * s, segment.hit ? color : "#bfdbfe", 18, 80);
          }
        }
      });

      if (step >= cast.flight_steps) {
        animation.aftermathAt = now;
        if (cast.shake) shake(6, 700);
        if (cast.ko?.length) {
          shake(10, 900);
          playBoom(14);
        }
        for (const aura of cast.auras ?? []) {
          const unit = (pending ?? shown)?.units.find((u) => u.id === aura.id);
          if (unit) {
            const s = scale();
            burst((unit.x + 0.5) * s, (unit.y - 1) * s, SPELL_COLORS[aura.kind] ?? "#fff", 26, 70);
          }
        }
        if (pending) {
          show(pending);
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
      const elapsed = now - animation.aftermathAt;
      const s = scale();

      if (elapsed < 500) {
        for (const [x0, y0, x1, y1] of animation.cast.beams) lightning(x0 * s, y0 * s, x1 * s, y1 * s, "#93c5fd");
      }

      const knockSteps = Math.max(0, ...animation.cast.knocks.map((k) => k.path.length));
      const slow = knockSpeed(animation.cast) < 1;

      const done =
        castStep(now, animation.aftermathAt, knockSpeed(animation.cast)) >= knockSteps &&
        elapsed > (slow ? 1300 : animation.cast.beams.length ? 500 : 250);

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
        const ty = focus[1] - VIEW_H * 0.55;
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

    const glide = (unit: Unit, dt: number) => {
      const s = scale();
      const prev = drawn.get(unit.id);
      if (!prev || unit.dead) {
        drawn.set(unit.id, [unit.x, unit.y]);
        return { x: unit.x, y: unit.y };
      }
      if (Math.hypot(unit.x - prev[0], unit.y - prev[1]) > 6) {
        const color = SPELL_COLORS.blink;
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

    const drawKnockoutBanner = (now: number) => {
      if (!animation || animation.aftermathAt === null) return;
      const elapsed = now - animation.aftermathAt;
      const slow = knockSpeed(animation.cast) < 1;
      if (slow) {
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
      }

    };

    // A strip in the top corner showing the whole world, every wizard and the view.
    const MINI = { w: 150, pad: 10 };
    const miniRect = () => {
      if (!shown) return null;
      const h = (MINI.w * shown.height) / shown.width;
      return { x: W - MINI.w - MINI.pad, y: MINI.pad, w: MINI.w, h };
    };

    const drawMinimap = () => {
      const r = miniRect();
      if (!shown || !r || !terrainCanvas) return;
      const k = r.w / shown.width;
      ctx.save();
      ctx.globalAlpha = 0.9;
      ctx.fillStyle = "rgba(15, 23, 42, 0.55)";
      ctx.fillRect(r.x, r.y, r.w, r.h);
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(terrainCanvas, r.x, r.y, r.w, r.h);
      ctx.fillStyle = palette().water;
      ctx.fillRect(r.x, r.y + shown.water_level * k, r.w, r.h - shown.water_level * k);
      for (const unit of shown.units) {
        if (unit.dead || unit.kind !== "wizard") continue;
        ctx.fillStyle = shown.players[unit.id]?.color ?? "#fff";
        ctx.strokeStyle = "#111827";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(r.x + (unit.x + 0.5) * k, r.y + (unit.y - 1) * k, unit.id === shown.current_id ? 3.5 : 2.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1.5;
      ctx.strokeRect(r.x + cam.x * k, r.y + cam.y * k, VIEW_W * k, VIEW_H * k);
      ctx.strokeStyle = "#111827";
      ctx.lineWidth = 2;
      ctx.strokeRect(r.x, r.y, r.w, r.h);
      ctx.restore();
    };

    // Off-screen wizards get an arrow at the edge so nobody gets lost.
    const drawOffscreenMarkers = () => {
      if (!shown) return;
      for (const unit of shown.units) {
        if (unit.dead || unit.kind !== "wizard") continue;
        const sx = (unit.x + 0.5 - cam.x) * CELL;
        if (sx >= 0 && sx <= W) continue;
        const left = sx < 0;
        const y = Math.max(20, Math.min(H - 20, (unit.y - 1 - cam.y) * CELL));
        const x = left ? 14 : W - 14;
        ctx.fillStyle = shown.players[unit.id]?.color ?? "#fff";
        ctx.strokeStyle = "#111827";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(x + (left ? -8 : 8), y);
        ctx.lineTo(x + (left ? 6 : -6), y - 8);
        ctx.lineTo(x + (left ? 6 : -6), y + 8);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
      }
    };

    const minimapJump = (px: number, py: number) => {
      const r = miniRect();
      if (!r || !shown || px < r.x || px > r.x + r.w || py < r.y || py > r.y + r.h) return false;
      const k = r.w / shown.width;
      cam.x = (px - r.x) / k - VIEW_W / 2;
      cam.y = (py - r.y) / k - VIEW_H / 2;
      clampCam();
      freeLookUntil = performance.now() + 4000;
      return true;
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
        ctx.drawImage(terrainCanvas, 0, 0, shown.width * CELL, shown.height * CELL);
        const caster = animation?.cast.caster_id;
        const knocked = knockedPositions(now);
        const units = shown.units.map((u) => {
          const at = knocked.get(u.id);
          if (at) {
            drawn.set(u.id, [at[0], at[1]]);
            return { ...u, x: at[0], y: at[1], dead: false };
          }
          return { ...u, ...glide(u, dt) };
        });

        for (const crate of shown.crates) drawCrate(crate, now);

        for (const unit of units) {
          if (unit.kind === "wizard") {
            const facing =
              unit.id === shown.viewer_id && aim
                ? Math.cos((aim.angle * Math.PI) / 180) >= 0 ? 1 : -1
                : unit.id === caster ? 1 : unit.x < shown.width / 2 ? 1 : -1;
            drawWizard(unit, now, facing);
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
      drawMinimap();
      drawKnockoutBanner(now);
      ctx.restore();
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
      charge = null;
      if (!canAct()) return;
      castLocked = true;
      this.pushEvent("cast", { angle: Math.round(aim.angle * 10) / 10, power: Math.round(power * 10) / 10 });
    };

    // Lobbed spells charge; beams fire at once; placed spells conjure where you click.
    const trigger = () => {
      const spell = spellDef();
      const wizard = myWizard();
      if (!canAct() || !aim || !spell || !wizard || spell.quick || charge) return;
      if (spell.place) {
        const target = placeTarget();
        if (!target || !target.inRange || target.sinks) return;
        castLocked = true;
        this.pushEvent("place", { x: Math.round(target.x * 10) / 10, y: Math.round(target.y * 10) / 10 });
      } else if (spell.gravity === 0) {
        castLocked = true;
        this.pushEvent("cast", { angle: Math.round(aim.angle * 10) / 10, power: 100 });
      } else {
        charge = { start: performance.now() };
      }
    };

    const updateAim = (event: PointerEvent) => {
      const wizard = myWizard();
      if (!wizard) return;
      const [x, y] = toCells(event);
      const dx = x - (wizard.x + 0.5);
      const dy = y - (wizard.y - 2);
      aim = { angle: (Math.atan2(-dy, dx) * 180) / Math.PI, power: 0 };
    };

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointer = { x: ((event.clientX - rect.left) / rect.width) * W, y: ((event.clientY - rect.top) / rect.height) * H };
      if (!charge) updateAim(event);
    };
    const onPointerLeave = () => {
      pointer = null;
    };
    const onPointerDown = (event: PointerEvent) => {
      if (event.button !== 0) return;
      canvas.focus();
      const rect = canvas.getBoundingClientRect();
      const px = ((event.clientX - rect.left) / rect.width) * W;
      const py = ((event.clientY - rect.top) / rect.height) * H;
      if (minimapJump(px, py)) return;
      // Touch and pen taps arrive without a hover first.
      pointer = { x: px, y: py };
      updateAim(event);
      trigger();
    };
    const onPointerUp = () => release();

    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return;
      const key = event.key.toLowerCase();
      if (key === "f" && !event.metaKey && !event.ctrlKey) {
        toggleFull();
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
        this.pushEvent("walk", { dir: key === "a" || key === "arrowleft" ? -1 : 1 });
      } else if (key === "w" || key === "arrowup" || key === "s" || key === "arrowdown") {
        event.preventDefault();
        if (!canAct() || performance.now() - lastWalk < 85) return;
        lastWalk = performance.now();
        this.pushEvent("rise", { dir: key === "w" || key === "arrowup" ? 1 : -1 });
      } else if (/^[0-9-]$/.test(key)) {
        const spell = shown.my_spells[key === "0" ? 9 : key === "-" ? 10 : Number(key) - 1];
        if (spell) this.pushEvent("select_spell", { spell });
      }
    };

    const onKeyUp = (event: KeyboardEvent) => {
      if (event.key === " ") release();
    };

    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointerleave", onPointerLeave);
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);

    this.handleEvent<ArenaState>("arena_state", receive);
    this.handleEvent("arena_unlock", () => {
      castLocked = false;
    });
    this.handleEvent<{ spell: string }>("arena_select", ({ spell }) => {
      selected = spell;
    });

    this.cleanup = () => {
      cancelAnimationFrame(rafId);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("pointerleave", onPointerLeave);
      canvas.removeEventListener("arena:fullscreen", toggleFull);
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      resizeObserver.disconnect();
      audio?.close();
    };
  },

  destroyed(this: SpellArenaHook) {
    this.cleanup?.();
  },
};

export default SpellArena;
