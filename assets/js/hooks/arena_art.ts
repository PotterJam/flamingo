// Painted art for the Spellslingers arena: the per-arena backdrop and ground texture,
// the wizard and minion sprite sheets, and the land itself, traced smooth from the
// server's cell grid and painted with an outline, a grass lip and darker depths.
// Physics never looks at any of this; it stays on the cells.

const BASE = "/images/spellslingers";

// Miner sheet frames, left to right, each WIZARD_W x WIZARD_H with the boots centred on
// the bottom edge, painted facing right: an 8-frame walk cycle, then single poses.
export const WIZARD = {
  walk: 0,
  idle: 8,
  blink: 9,
  scratch: 10,
  aimUp: 11,
  aim: 12,
  aimDown: 13,
  windup: 14,
  release: 15,
  crouch: 16,
  rise: 17,
  fall: 18,
  land: 19,
  hurt: 20,
  tumble: 21,
  cheer: 22,
  jig: 23,
} as const;
// Where the crystal on the pick sits in the aiming and throwing frames, as fractions of
// the cell's height: across from the boots, and up from them.
export const CRYSTAL: Record<number, [number, number]> = {
  8: [0.224, 0.536],
  11: [0.323, 0.742],
  12: [0.464, 0.408],
  13: [0.302, 0.159],
  14: [-0.159, 0.704],
  15: [0.381, 0.184],
};
export const WIZARD_W = 280;
export const WIZARD_H = 240;
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

// The wizard is painted in one blue robe; each player's copy swaps that blue for their
// colour, keeping the painted light and shade.
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

// Blasts leave their craters ringed in charred earth, like Worms: a band of near-black
// right at the edge of the hole that browns out into the ground around it. Drawn
// source-atop on painted land, so it only darkens land. The band starts inside the
// carved radius because the traced edge sits a little inside it.
function scorch(c: CanvasRenderingContext2D, x: number, y: number, r: number) {
  const R = LAND_RES;
  const outer = r + 3.2;
  const g = c.createRadialGradient(x * R, y * R, Math.max(0, r - 1.5) * R, x * R, y * R, outer * R);
  const at = (d: number) => Math.max(0, Math.min(1, (d - (r - 1.5)) / (outer - (r - 1.5))));
  g.addColorStop(0, "rgba(22,12,8,0.92)");
  g.addColorStop(at(r + 0.9), "rgba(30,16,10,0.85)");
  g.addColorStop(at(r + 1.8), "rgba(70,34,18,0.45)");
  g.addColorStop(1, "rgba(70,34,18,0)");
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
