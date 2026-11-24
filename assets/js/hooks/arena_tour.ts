// Four hints on the player's own first turn, each pointing at the real control and
// clearing itself once the player does what it says (or on Next), so it teaches without
// holding the clock up. It rings what it points at without dimming the arena. If the
// turn ends mid-tour it waits for the next one. It shows once per browser.

const DONE_KEY = "spellslingers_tour_done";

type Box = { left: number; top: number; right: number; bottom: number; width: number; height: number };
type Step = {
  target: string;
  text: string;
  place: (r: Box, coach: DOMRect) => [number, number];
  // What the player does that completes this step.
  done: (seen: Seen) => boolean;
};
type Seen = { aimed: number; keys: Set<string>; spells: boolean };

const spellsOpen = () => {
  const panel = document.getElementById("arena-spells");
  return !!panel && getComputedStyle(panel).display !== "none";
};

// The viewer's own wizard, as the arena hook reports it, with room for the hat and name.
const WIZARD = "wizard";
const wizardBox = (): Box | null => {
  const canvas = document.getElementById("arena-canvas") as
    | (HTMLElement & { viewerPoint?: () => { x: number; y: number; k: number } | null })
    | null;
  const p = canvas?.viewerPoint?.();
  if (!p) return null;
  const w = 9 * p.k;
  const top = p.y - 12 * p.k;
  const bottom = p.y + 2 * p.k;
  return { left: p.x - w / 2, right: p.x + w / 2, top, bottom, width: w, height: bottom - top };
};

// Beside the wizard, on whichever side has room.
const besideWizard = (r: Box, c: DOMRect): [number, number] => {
  const right = r.right + 24;
  const x = right + c.width < window.innerWidth - 8 ? right : r.left - c.width - 24;
  return [x, r.top + (r.height - c.height) / 2];
};

const steps = (walk: string, jump: string): Step[] => [
  {
    target: WIZARD,
    text: "Your turn! This is you. Move the mouse to aim at another wizard.",
    place: besideWizard,
    done: (seen) => seen.aimed > 25,
  },
  {
    target: "#arena-spell-chip",
    text: "Your spell. Tab or right-click opens the whole arsenal, the same for every wizard; the badge on each is how many you have left. Crates bring more.",
    place: (r, c) => [r.left, r.top - c.height - 16],
    // Once they have looked through the panel and closed it again.
    done: (seen) => seen.spells && !spellsOpen(),
  },
  {
    target: "#arena-moves",
    text: `Hold A / D to walk. Too steep? W high-jumps and S long-jumps the way you face, for ${jump} steps each. You get ${walk} steps a turn.`,
    place: (r, c) => [r.right - c.width, r.top - c.height - 16],
    done: (seen) => ["a", "d", "w", "s", "arrowleft", "arrowright", "arrowup", "arrowdown"].some((k) => seen.keys.has(k)),
  },
  {
    target: WIZARD,
    text: "Hold the mouse button or Space to charge, then let go to throw. Right-click or Esc cancels. Esc on its own opens the menu.",
    place: besideWizard,
    done: () => false,
  },
];

interface TourHook {
  el: HTMLElement;
  stop?: () => void;
  pause?: (paused: boolean) => void;
}

const start = (hook: TourHook) => {
  const list = steps(hook.el.dataset.walk || "40", hook.el.dataset.jump || "5");
  let step = 0;
  let raf = 0;

  const seen: Seen = { aimed: 0, keys: new Set(), spells: false };
  const onMove = () => (seen.aimed += 1);
  const onKey = (event: KeyboardEvent) => seen.keys.add(event.key.toLowerCase());
  window.addEventListener("pointermove", onMove);
  window.addEventListener("keydown", onKey);

  const hole = document.createElement("div");
  hole.className = "arena-tour-hole";
  const coach = document.createElement("div");
  coach.className = "arena-tour-coach";
  coach.id = "arena-tour";
  document.body.append(hole, coach);

  const finish = () => {
    localStorage.setItem(DONE_KEY, "1");
    hook.stop?.();
  };

  const draw = () => {
    const s = list[step];
    coach.innerHTML = `<div class="flex gap-2"><span class="arena-tour-num">${step + 1}</span><span>${s.text}</span></div>
      <div class="mt-2.5 flex items-center justify-between">
        <button type="button" data-tour="skip" class="cursor-pointer font-bold underline">Skip</button>
        <span class="text-xs">${step + 1} / ${list.length}</span>
        <button type="button" data-tour="next" class="cursor-pointer border-2 border-black bg-white px-3 py-0.5 font-black">${step === list.length - 1 ? "Got it" : "Next"}</button>
      </div>`;
  };

  // Pointing at the wizard brings the camera round to it when it is out of view,
  // as clicking its name in the rail does; a cast in flight still takes the camera.
  let lookedAt = 0;
  const advance = () => {
    if (step === list.length - 1) finish();
    else {
      step += 1;
      draw();
    }
  };

  const place = () => {
    seen.spells ||= spellsOpen();
    if (!coach.hidden && list[step].done(seen)) {
      // A beat to see the hint go, then the next one.
      seen.aimed = 0;
      seen.keys.clear();
      seen.spells = false;
      advance();
      if (!hook.stop) return;
    }
    const target = list[step].target;
    const r = target === WIZARD ? wizardBox() : document.querySelector(target)?.getBoundingClientRect();
    const stage = document.getElementById("arena-stage")?.getBoundingClientRect();
    if (r && stage && target === WIZARD) {
      const inView = r.left > stage.left && r.right < stage.right && r.top > stage.top && r.bottom < stage.bottom;
      if (!inView && performance.now() - lookedAt > 4000) {
        lookedAt = performance.now();
        document.getElementById("arena-canvas")?.dispatchEvent(new CustomEvent("arena:focus"));
      }
    }
    if (r) {
      Object.assign(hole.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      const c = coach.getBoundingClientRect();
      const [x, y] = list[step].place(r, c);
      // Kept inside the arena, or the window when the arena is scrolled partly away.
      const left = Math.max(8, stage?.left ?? 0);
      const right = Math.min(window.innerWidth, stage?.right ?? window.innerWidth) - 8;
      const top = Math.max(8, stage?.top ?? 0);
      const bottom = Math.min(window.innerHeight, stage?.bottom ?? window.innerHeight) - 8;
      coach.style.left = `${Math.max(left, Math.min(right - c.width, x))}px`;
      coach.style.top = `${Math.max(top, Math.min(bottom - c.height, y))}px`;
    }
    raf = requestAnimationFrame(place);
  };

  coach.addEventListener("click", (event) => {
    const action = (event.target as HTMLElement).closest<HTMLElement>("[data-tour]")?.dataset.tour;
    if (action === "skip") finish();
    if (action === "next") advance();
  });

  hook.stop = () => {
    cancelAnimationFrame(raf);
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("keydown", onKey);
    hole.remove();
    coach.remove();
    hook.stop = undefined;
    hook.pause = undefined;
  };
  hook.pause = (paused) => {
    // The last hint is taught by the throw itself: once the turn ends, it is done.
    if (paused && step === list.length - 1) {
      finish();
      return;
    }
    hole.hidden = paused;
    coach.hidden = paused;
  };

  draw();
  place();
};

const ArenaTour = {
  mounted(this: TourHook) {
    this.updated();
  },
  updated(this: TourHook) {
    const active = this.el.dataset.active === "true";
    if (this.pause) this.pause(!active);
    else if (active && !localStorage.getItem(DONE_KEY)) start(this);
  },
  destroyed(this: TourHook) {
    this.stop?.();
  },
};

export default ArenaTour;
