// Painted art for the Spellslingers arena: the per-arena backdrop and ground texture,
// the wizard and minion sprite sheets, and the land itself, traced smooth from the
// server's cell grid and painted with an outline, a grass lip and darker depths.
// Physics never looks at any of this; it stays on the cells.

const BASE = "/images/spellslingers";

// Flamingo sheet frames, left to right, each WIZARD_W x WIZARD_H with the feet centred on
// the bottom edge, painted facing right: an 8-frame strut, then single poses.
export const WIZARD = {
  walk: 0,
  idle: 8,
  blink: 9,
  preen: 10,
  aimUp: 11,
  aim: 12,
  aimDown: 13,
  windup: 14,
  release: 15,
  crouch: 16,
  rise: 17,
  flapUp: 18,
  flapDown: 19,
  fall: 20,
  land: 21,
  hurt: 22,
  tumble: 23,
  stand: 24,
  follow: 25,
  recover: 26,
  dizzy: 27,
  glance: 28,
  cheer: 29,
  dance: 30,
  front: 31,
} as const;
// Where the wing tip is in the aiming and throwing frames, as fractions of the cell's
// height: across from the feet, and up from them. Spells glow and leave from there.
export const WINGTIP: Record<number, [number, number]> = {
  12: [0.57, 0.487],
  15: [0.607, 0.507],
  25: [0.543, 0.563],
};
export const WIZARD_W = 400;
export const WIZARD_H = 300;

// The aiming and throwing frames come apart into layers, so the wing and head follow the
// aim exactly instead of snapping between painted angles: the wing turns about its
// shoulder and the head and neck about the neck's base. Each joint keeps a disc of the
// body painted over it, so a turned piece never opens a gap there. In pixels of the
// frame's cell; `cut` outlines the piece and `angle` is how far above level the painted
// wing points.
type Joint = { pivot: [number, number]; r: number; cut: number[] };
type Rig = { wing: Joint & { angle: number }; head: Joint };
export const RIG: Record<number, Rig> = {
  [WIZARD.aim]: {
    wing: {
      pivot: [256, 172],
      r: 24,
      angle: 11,
      cut: [250, 150, 275, 146, 300, 136, 330, 126, 365, 124, 398, 136, 398, 165, 370, 182, 330, 193, 300, 198, 270, 198, 250, 198],
    },
    head: { pivot: [251, 149], r: 11, cut: [225, 55, 345, 55, 345, 132, 300, 136, 266, 144, 260, 150, 238, 150, 230, 135, 225, 115] },
  },
  [WIZARD.release]: {
    wing: {
      pivot: [268, 174],
      r: 24,
      angle: 22,
      cut: [272, 152, 285, 150, 320, 136, 355, 120, 398, 118, 398, 150, 370, 172, 340, 184, 300, 196, 272, 202],
    },
    head: { pivot: [255, 153], r: 11, cut: [230, 48, 345, 48, 345, 120, 320, 128, 300, 136, 270, 146, 263, 154, 242, 154, 236, 140, 230, 120] },
  },
};

type Layers = { body: HTMLCanvasElement; wing: HTMLCanvasElement; head: HTMLCanvasElement };
const rigged = new WeakMap<HTMLCanvasElement, Map<number, Layers>>();
const cell = (paint: (c: CanvasRenderingContext2D) => void) => {
  const canvas = document.createElement("canvas");
  canvas.width = WIZARD_W;
  canvas.height = WIZARD_H;
  paint(canvas.getContext("2d")!);
  return canvas;
};
const outline = (c: CanvasRenderingContext2D, pts: number[]) => {
  c.beginPath();
  for (let i = 0; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1]);
  c.closePath();
};

// A rigged frame's layers, cut once per tinted sheet.
function layersOf(sheet: HTMLCanvasElement, frame: number) {
  let byFrame = rigged.get(sheet);
  if (!byFrame) rigged.set(sheet, (byFrame = new Map()));
  const cached = byFrame.get(frame);
  if (cached) return cached;
  const rig = RIG[frame];
  const art = (c: CanvasRenderingContext2D) => c.drawImage(sheet, frame * WIZARD_W, 0, WIZARD_W, WIZARD_H, 0, 0, WIZARD_W, WIZARD_H);
  const piece = (j: Joint) =>
    cell((c) => {
      outline(c, j.cut);
      c.fill();
      // Its own share of the joint stays inside where the body's disc is solid, so the
      // kerchief and chest painted there never peek out from behind it as it turns.
      c.beginPath();
      c.arc(j.pivot[0], j.pivot[1], j.r * 0.8, 0, Math.PI * 2);
      c.fill();
      c.globalCompositeOperation = "source-in";
      art(c);
    });
  // The joint's disc fades out at its rim, so the still body melts into the turned piece.
  const disc = (j: Joint) =>
    cell((c) => {
      const [x, y] = j.pivot;
      const g = c.createRadialGradient(x, y, 0, x, y, j.r);
      g.addColorStop(0.85, "#000");
      g.addColorStop(1, "rgba(0,0,0,0)");
      c.fillStyle = g;
      c.fillRect(0, 0, WIZARD_W, WIZARD_H);
      c.globalCompositeOperation = "source-in";
      art(c);
    });
  const body = cell((c) => {
    art(c);
    c.globalCompositeOperation = "destination-out";
    for (const j of [rig.wing, rig.head]) {
      outline(c, j.cut);
      c.fill();
    }
    c.globalCompositeOperation = "source-over";
    c.drawImage(disc(rig.wing), 0, 0);
    c.drawImage(disc(rig.head), 0, 0);
  });
  const layers = { body, wing: piece(rig.wing), head: piece(rig.head) };
  byFrame.set(frame, layers);
  return layers;
}

// Paints a rigged frame into `out` (a WIZARD_W x WIZARD_H canvas) with the wing pointing
// `wing` degrees above level and the head turned `head` degrees up, both from its facing.
export function poseRig(out: HTMLCanvasElement, sheet: HTMLCanvasElement, frame: number, wing: number, head: number) {
  const rig = RIG[frame];
  const layers = layersOf(sheet, frame);
  const c = out.getContext("2d")!;
  c.clearRect(0, 0, WIZARD_W, WIZARD_H);
  const turn = (img: HTMLCanvasElement, j: Joint, deg: number) => {
    const [x, y] = j.pivot;
    c.save();
    c.translate(x, y);
    c.rotate((-deg * Math.PI) / 180);
    c.translate(-x, -y);
    c.drawImage(img, 0, 0);
    c.restore();
  };
  // Behind the body, so a wing swung low passes behind the legs and the neck tucks into
  // the neckerchief.
  turn(layers.wing, rig.wing, wing - rig.wing.angle);
  turn(layers.head, rig.head, head);
  c.drawImage(layers.body, 0, 0);
  return out;
}

// Where the wing tip is in a rigged frame with its wing at `wing` degrees, as WINGTIP gives
// it: across from the feet and up from them, as fractions of the cell's height.
export function rigTip(frame: number, wing: number): [number, number] {
  const { pivot, angle } = RIG[frame].wing;
  const [tx, ty] = WINGTIP[frame];
  const dx = tx * WIZARD_H + WIZARD_W / 2 - pivot[0];
  const dy = WIZARD_H - ty * WIZARD_H - pivot[1];
  const r = ((angle - wing) * Math.PI) / 180;
  const x = pivot[0] + dx * Math.cos(r) - dy * Math.sin(r);
  const y = pivot[1] + dx * Math.sin(r) + dy * Math.cos(r);
  return [(x - WIZARD_W / 2) / WIZARD_H, (WIZARD_H - y) / WIZARD_H];
}
// Crate sheet frames, each CRATE_SIZE square, standing on the bottom edge.
export const CRATE_FRAME: Record<string, number> = { health: 0, mana: 1 };
export const CRATE_SIZE = 200;
// The spells sheet: one CELL square frame per spell (its `sprite`), centred in the cell.
export const SPELL_CELL = 128;
// The explosion sheet: BOOM_FRAMES square frames of BOOM_CELL, flash to last wisps of smoke.
export const BOOM_CELL = 256;
export const BOOM_FRAMES = 8;

type Rgb = [number, number, number];

export type ArtPalette = {
  grass: Rgb[];
};

// Images load in the background; until one has, the renderer draws its older look.
// Without a browser (the hook's tests) nothing loads at all.
export function loadArt(onLoad: (name: string) => void) {
  const load = (name: string) => {
    if (typeof Image === "undefined") return null;
    const img = new Image();
    img.decoding = "async";
    img.onload = () => onLoad(name);
    img.src = `${BASE}/${name}.webp`;
    return img;
  };
  const maps = ["isles", "flamingo", "castles", "cavern", "archipelago"];
  return {
    wizard: load("wizard"),
    crates: load("crates"),
    spells: load("spells"),
    boom: load("boom"),
    backdrops: Object.fromEntries(maps.map((m) => [m, load(`bg_${m}`)])) as Record<string, HTMLImageElement | null>,
    textures: Object.fromEntries(maps.map((m) => [m, load(`tex_${m}`)])) as Record<string, HTMLImageElement | null>,
  };
}

export const ready = (img: HTMLImageElement | null | undefined): img is HTMLImageElement =>
  !!img && img.complete && img.naturalWidth > 0;

function hexRgb(hex: string): Rgb {
  const n = parseInt(hex.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbHsl([r, g, b]: Rgb): Rgb {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}

function hslRgb([h, s, l]: Rgb): Rgb {
  if (s === 0) return [l * 255, l * 255, l * 255];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const f = (t: number) => {
    t = (t + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255];
}

// The flamingo is painted with one blue neckerchief; each player's copy swaps that blue
// for their colour, keeping the painted light and shade.
const tinted = new Map<string, HTMLCanvasElement>();
export function wizardSheet(img: HTMLImageElement, color: string) {
  const cached = tinted.get(color);
  if (cached) return cached;
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = img.naturalHeight;
  const c = canvas.getContext("2d")!;
  c.drawImage(img, 0, 0);
  const data = c.getImageData(0, 0, canvas.width, canvas.height);
  const px = data.data;
  const [th, ts, tl] = rgbHsl(hexRgb(color));
  for (let i = 0; i < px.length; i += 4) {
    const r = px[i];
    const g = px[i + 1];
    const b = px[i + 2];
    if (px[i + 3] === 0 || b < r + 35 || b < g + 20) continue;
    const [, , l] = rgbHsl([r, g, b]);
    const out = hslRgb([th, Math.min(1, ts * 1.05), Math.min(0.92, (l * tl) / 0.52)]);
    px[i] = out[0];
    px[i + 1] = out[1];
    px[i + 2] = out[2];
  }
  c.putImageData(data, 0, 0);
  tinted.set(color, canvas);
  return canvas;
}

// Pixels per cell in the painted land. The view shows about 10 to 20 screen pixels per
// cell, so 8 keeps the outline crisp without a huge canvas.
export const LAND_RES = 8;

// Traces the land smooth from the cell grid: the grid is scaled up with smoothing and
// blurred, and the edge sits where it crosses half. Then the ground texture fills it,
// a grass lip runs along every top surface with a shadow under it, and a dark outline
// goes around the whole shape.
export function paintLand(
  cells: Uint8Array,
  width: number,
  height: number,
  texture: HTMLImageElement,
  pal: ArtPalette,
  scorches: { x: number; y: number; r: number }[] = [],
) {
  const R = LAND_RES;
  // The grid extends past every edge of the world, so land touching one (a cave's
  // ceiling included) runs off it instead of being rounded and outlined there.
  const PAD = 4;
  const mw = width + PAD * 2;
  const mh = height + PAD * 2;
  const mask = document.createElement("canvas");
  mask.width = mw;
  mask.height = mh;
  const mctx = mask.getContext("2d")!;
  const mimg = mctx.createImageData(mw, mh);
  for (let y = 0; y < mh; y++) {
    const cy = Math.max(0, Math.min(height - 1, y - PAD));
    for (let x = 0; x < mw; x++) {
      const cx = Math.max(0, Math.min(width - 1, x - PAD));
      if (cells[cy * width + cx]) mimg.data.set([255, 255, 255, 255], (y * mw + x) * 4);
    }
  }
  mctx.putImageData(mimg, 0, 0);

  const w = width * R;
  const h = height * R;
  const smooth = document.createElement("canvas");
  smooth.width = w;
  smooth.height = h;
  const sctx = smooth.getContext("2d", { willReadFrequently: true })!;
  sctx.imageSmoothingEnabled = true;
  sctx.imageSmoothingQuality = "high";
  sctx.filter = `blur(${R * 0.55}px)`;
  sctx.drawImage(mask, -PAD * R, -PAD * R, mw * R, mh * R);
  sctx.filter = "none";
  const alpha = sctx.getImageData(0, 0, w, h).data;

  // The texture, tiled so one tile spans about 28 cells.
  const land = document.createElement("canvas");
  land.width = w;
  land.height = h;
  const lctx = land.getContext("2d", { willReadFrequently: true })!;
  const pattern = lctx.createPattern(texture, "repeat")!;
  const tile = (28 * R) / texture.naturalWidth;
  pattern.setTransform?.(new DOMMatrix([tile, 0, 0, tile, 0, 0]));
  lctx.fillStyle = pattern;
  lctx.fillRect(0, 0, w, h);
  const out = lctx.getImageData(0, 0, w, h);
  const px = out.data;

  const grass = Math.round(R * 1.15);
  const [hi, mid, lo] = pal.grass;
  for (let x = 0; x < w; x++) {
    // How far down from the open air above each pixel is, column by column. Land at the
    // top edge carries on above it, so it gets no crust there.
    let depth = alpha[x * 4 + 3] >= 128 ? grass : 0;
    for (let y = 0; y < h; y++) {
      const i = (y * w + x) * 4;
      const a = alpha[i + 3];
      if (a < 128) {
        depth = 0;
        px[i + 3] = 0;
        continue;
      }
      // A soft edge a pixel or two wide, so the outline is not jagged.
      px[i + 3] = Math.min(255, (a - 128) * 5 + 64);
      if (depth < grass) {
        const c = depth < 2 ? hi : depth > grass - 2 ? lo : mid;
        px[i] = c[0];
        px[i + 1] = c[1];
        px[i + 2] = c[2];
      } else {
        // A shadow just under the grass. Only that: shading by depth below the
        // surface would leave light columns under every hole.
        if (depth - grass < R * 0.6) {
          px[i] *= 0.68;
          px[i + 1] *= 0.68;
          px[i + 2] *= 0.68;
        }
      }
      depth++;
    }
  }
  lctx.putImageData(out, 0, 0);

  // A dark outline: the shape's silhouette, stamped around it, under the land.
  const outline = document.createElement("canvas");
  outline.width = w;
  outline.height = h;
  const octx = outline.getContext("2d")!;
  octx.drawImage(land, 0, 0);
  octx.globalCompositeOperation = "source-in";
  octx.fillStyle = "#1c1917";
  octx.fillRect(0, 0, w, h);

  const result = document.createElement("canvas");
  result.width = w;
  result.height = h;
  const rctx = result.getContext("2d")!;
  const t = Math.max(2, Math.round(R * 0.35));
  for (let a = 0; a < 8; a++) {
    rctx.drawImage(outline, Math.round(Math.cos((a * Math.PI) / 4) * t), Math.round(Math.sin((a * Math.PI) / 4) * t));
  }
  rctx.drawImage(land, 0, 0);
  rctx.globalCompositeOperation = "source-atop";
  for (const { x, y, r } of scorches) scorch(rctx, x, y, r);
  return result;
}

// Blasts leave their craters ringed in charred earth, like Worms: a dark band right at
// the edge of the hole that browns out into the ground around it. Drawn source-atop on
// painted land, so it only darkens land. The band starts inside the carved radius
// because the traced edge sits a little inside it. It stays translucent and a couple of
// cells wide, so the texture shows through: a sliver of land left over a crater, or a
// whole thin platform, still reads as ground to stand on rather than part of the hole.
function scorch(c: CanvasRenderingContext2D, x: number, y: number, r: number) {
  const R = LAND_RES;
  const outer = r + 2.4;
  const g = c.createRadialGradient(x * R, y * R, Math.max(0, r - 1.5) * R, x * R, y * R, outer * R);
  const at = (d: number) => Math.max(0, Math.min(1, (d - (r - 1.5)) / (outer - (r - 1.5))));
  g.addColorStop(0, "rgba(30,14,9,0.74)");
  g.addColorStop(at(r + 0.7), "rgba(36,18,11,0.62)");
  g.addColorStop(at(r + 1.5), "rgba(64,30,16,0.3)");
  g.addColorStop(1, "rgba(64,30,16,0)");
  c.fillStyle = g;
  c.fillRect((x - outer) * R, (y - outer) * R, outer * 2 * R, outer * 2 * R);
}

// Cuts a blast's crater straight out of land painted by paintLand, with the outline
// and scorched rim a full repaint would give it, in well under a frame.
export function carveLand(land: HTMLCanvasElement, x: number, y: number, r: number) {
  const R = LAND_RES;
  const c = land.getContext("2d")!;
  c.save();
  c.globalCompositeOperation = "destination-out";
  c.beginPath();
  c.arc(x * R, y * R, r * R, 0, Math.PI * 2);
  c.fill();
  c.globalCompositeOperation = "source-atop";
  scorch(c, x, y, r);
  // The dark outline paintLand stamps around every edge, here around the new one.
  const t = Math.max(2, Math.round(R * 0.35));
  c.strokeStyle = "#1c1917";
  c.lineWidth = t * 2;
  c.beginPath();
  c.arc(x * R, y * R, r * R + t * 0.5, 0, Math.PI * 2);
  c.stroke();
  c.restore();
}
