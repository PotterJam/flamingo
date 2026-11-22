// A five-step tour that points at the real controls and ends at the ? button, which opens
// How to play any time. It runs the first time a player watches someone else's turn, so
// it never costs them their own; if their turn comes mid-tour it waits, then carries on.
// It shows once per browser.

const DONE_KEY = "spellslingers_tour_done";

type Box = { left: number; top: number; right: number; bottom: number; width: number; height: number };
type Step = { target: string; text: string; place: (r: Box, coach: DOMRect) => [number, number] };

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

const steps = (walk: string): Step[] => [
  {
    target: WIZARD,
    text: "This is you, with the arrow overhead. Move the mouse to aim at another wizard.",
    place: besideWizard,
  },
  {
    target: WIZARD,
    text: "Hold the mouse button or Space to charge; you can keep aiming while it fills. Let go to throw. Changed your mind? Right-click or Esc cancels.",
    place: besideWizard,
  },
  {
    target: "#spellbook",
    text: "Pick a spell here, or press the key shown on it. Some charge, beams fire on click, summons go where you click.",
    place: (r, c) => [r.left + 160, r.top - c.height - 16],
  },
  {
    target: "#arena-moves",
    text: `Walk with A / D, the arrow keys or these buttons. You get ${walk} steps a turn.`,
    place: (r, c) => [r.left - 200, r.top - c.height - 16],
  },
  {
    target: "#arena-help-button",
    text: "Forgot something? This opens How to play any time, mid-game too.",
    place: (r) => [r.left - 230, r.bottom + 12],
  },
];

interface TourHook {
  el: HTMLElement;
  stop?: () => void;
  pause?: (paused: boolean) => void;
}

const start = (hook: TourHook) => {
  const list = steps(hook.el.dataset.walk || "40");
  let step = 0;
  let raf = 0;

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

  const place = () => {
    const target = list[step].target;
    const r = target === WIZARD ? wizardBox() : document.querySelector(target)?.getBoundingClientRect();
    if (r) {
      Object.assign(hole.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      const c = coach.getBoundingClientRect();
      const [x, y] = list[step].place(r, c);
      coach.style.left = `${Math.max(8, Math.min(window.innerWidth - c.width - 8, x))}px`;
      coach.style.top = `${Math.max(8, Math.min(window.innerHeight - c.height - 8, y))}px`;
    }
    raf = requestAnimationFrame(place);
  };

  coach.addEventListener("click", (event) => {
    const action = (event.target as HTMLElement).closest<HTMLElement>("[data-tour]")?.dataset.tour;
    if (action === "skip") finish();
    if (action === "next") {
      if (step === list.length - 1) finish();
      else {
        step += 1;
        draw();
      }
    }
  });

  hook.stop = () => {
    cancelAnimationFrame(raf);
    hole.remove();
    coach.remove();
    hook.stop = undefined;
    hook.pause = undefined;
  };
  hook.pause = (paused) => {
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
