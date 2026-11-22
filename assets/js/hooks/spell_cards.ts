import { demo, scene } from "./spell_clips";

// Spell cards open on intent, never on a click: a long hover (with a bar filling along
// the bottom of the button while it waits) or a press-and-hold, which also works on
// touch and leaves the selection alone. Once a card is open, moving to another spell
// swaps it at once; leaving the spells closes it. The server renders each card into a
// <template id="spell-card-ID">; this hook copies it into its own slot and adds the clip.

const HOLD_MS = 350;
const DELAY_MS = 700;

const still = (svg: SVGSVGElement | null) => {
  if (!svg || !window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  // One frame of the cast, mid-flight, instead of a loop.
  svg.pauseAnimations();
  svg.setCurrentTime(2);
};

interface CardsHook {
  el: HTMLElement;
  cleanup?: () => void;
}

export const SpellCards = {
  mounted(this: CardsHook) {
    const root = this.el;
    const slot = root.querySelector<HTMLElement>("[data-card-slot]")!;
    const bar = root.querySelector<HTMLElement>("[data-card-wait]")!;
    const hot = root.querySelector<HTMLStyleElement>("style[data-card-hot]")!;
    let open: string | null = null;
    let waiting: string | null = null;
    let timer = 0;
    let leaveTimer = 0;
    let held: { id: string; opened: boolean } | null = null;
    let swallowClick = false;

    const local = (target: HTMLElement) => {
      const r = target.getBoundingClientRect();
      const box = root.getBoundingClientRect();
      return { left: r.left - box.left, top: r.top - box.top, right: r.right - box.left, width: r.width, height: r.height, box };
    };

    const hideWait = () => {
      bar.style.transition = "none";
      bar.style.width = "0";
      bar.hidden = true;
    };

    const showWait = (target: HTMLElement, ms: number) => {
      const at = local(target);
      Object.assign(bar.style, { left: `${at.left}px`, top: `${at.top + at.height - 4}px`, width: "0", transition: "none" });
      bar.hidden = false;
      // Next frame, so the width animates from zero.
      requestAnimationFrame(() => {
        bar.style.transition = `width ${ms}ms linear`;
        bar.style.width = `${at.width}px`;
      });
    };

    const close = () => {
      window.clearTimeout(timer);
      waiting = null;
      hideWait();
      if (!open) return;
      open = null;
      slot.replaceChildren();
      hot.textContent = "";
    };

    const show = (id: string, target: HTMLElement) => {
      const template = document.getElementById(`spell-card-${id}`) as HTMLTemplateElement | null;
      window.clearTimeout(timer);
      waiting = null;
      hideWait();
      if (!template) return;
      const fresh = open !== id;
      open = id;
      slot.replaceChildren(template.content.cloneNode(true));
      const card = slot.firstElementChild as HTMLElement;
      const clip = card.querySelector<HTMLElement>("[data-clip]");
      if (clip) {
        clip.innerHTML = demo({ id, name: template.dataset.name, input: template.dataset.input });
        still(clip.querySelector("svg"));
      }
      if (fresh) card.classList.add("spell-card-pop");
      // Mark the spell the card belongs to (a style rule, so LiveView patches keep it).
      hot.textContent =
        target.dataset.cardPlace === "side"
          ? `#${root.id} [data-card="${id}"][data-card-place="side"] { background: #fef3c7; outline: 2px solid #000; }`
          : "";
      // In the book picker the card wears its book's colour.
      const head = card.querySelector<HTMLElement>("[data-card-head]");
      if (head && target.dataset.cardColor) head.style.background = target.dataset.cardColor;

      // Above the button in the dock; beside the spell in the book picker.
      const at = local(target);
      const w = card.offsetWidth;
      const h = card.offsetHeight;
      let left: number;
      let top: number;
      if (target.dataset.cardPlace === "side") {
        // Beside the whole book, lined up with its top, so its header stays visible.
        const book = local(target.closest<HTMLElement>("[data-card-anchor]") ?? target);
        left = book.right + 14;
        if (left + w > at.box.width - 4) left = book.left - w - 14;
        top = book.top;
      } else {
        left = at.left - 6;
        top = at.top - h - 12;
      }
      left = Math.max(4, Math.min(at.box.width - w - 4, left));
      top = Math.max(4, Math.min(at.box.height - h - 4, top));
      Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
    };

    const cardTarget = (node: EventTarget | null) =>
      node instanceof Element ? (node.closest("[data-card]") as HTMLElement | null) : null;

    const onOver = (event: PointerEvent) => {
      if (event.pointerType === "touch" || held) return;
      const target = cardTarget(event.target);
      if (!target) return;
      const id = target.dataset.card!;
      window.clearTimeout(leaveTimer);
      if (open === id || waiting === id) return;
      window.clearTimeout(timer);
      if (open) return show(id, target);
      const ms = Number(target.dataset.cardDelay) || DELAY_MS;
      waiting = id;
      showWait(target, ms);
      timer = window.setTimeout(() => show(id, target), ms);
    };

    const onOut = (event: PointerEvent) => {
      if (held || !cardTarget(event.target)) return;
      if (cardTarget(event.relatedTarget)) return;
      // A short grace, so crossing the gap between two spells or a layout shift
      // under a still pointer doesn't close the card.
      window.clearTimeout(leaveTimer);
      leaveTimer = window.setTimeout(() => {
        if (!held && !root.querySelector("[data-card]:hover")) close();
      }, 150);
    };

    const onDown = (event: PointerEvent) => {
      swallowClick = false;
      const target = cardTarget(event.target);
      if (!target || event.button !== 0) return;
      const id = target.dataset.card!;
      window.clearTimeout(timer);
      hideWait();
      waiting = null;
      held = { id, opened: false };
      timer = window.setTimeout(() => {
        if (!held) return;
        held.opened = true;
        show(id, target);
      }, HOLD_MS);
    };

    const onUp = () => {
      if (!held) return;
      const wasOpened = held.opened;
      held = null;
      window.clearTimeout(timer);
      // A press-and-hold only shows the card; a short press selects and shows nothing.
      if (wasOpened) swallowClick = true;
      close();
    };

    // Runs before LiveView's phx-click, which listens further up.
    const onClick = (event: MouseEvent) => {
      if (!swallowClick) return;
      swallowClick = false;
      event.preventDefault();
      event.stopPropagation();
    };

    const onContextMenu = (event: Event) => {
      if (cardTarget(event.target)) event.preventDefault();
    };

    root.addEventListener("pointerover", onOver);
    root.addEventListener("pointerout", onOut);
    root.addEventListener("pointerdown", onDown);
    root.addEventListener("click", onClick, true);
    root.addEventListener("contextmenu", onContextMenu);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);

    this.cleanup = () => {
      window.clearTimeout(timer);
      window.clearTimeout(leaveTimer);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
    };
  },

  destroyed(this: CardsHook) {
    this.cleanup?.();
  },
};

// A book's still, drawn once into its own phx-update="ignore" element.
export const SpellScene = {
  mounted(this: { el: HTMLElement }) {
    this.el.innerHTML = scene(this.el.dataset.scene);
    // The picker shows a slightly wider crop than the 2:1 drawing.
    this.el.querySelector("svg")?.setAttribute("preserveAspectRatio", "xMidYMid slice");
  },
};
