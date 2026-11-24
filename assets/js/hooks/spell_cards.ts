// The spell panel works like Worms' weapon panel: pointing at a spell shows its name,
// numbers and traits under the tray at once; away from the tray it goes back to the spell
// you have selected. The server renders every spell's pane and shows the selected one;
// all the panes share one grid cell, so the tray is always the tallest one's size and
// never jumps. This hook only overrides which pane is visible, through a style rule in an
// ignored element, so LiveView patches keep it.

interface CardsHook {
  el: HTMLElement;
}

export const SpellCards = {
  mounted(this: CardsHook) {
    const root = this.el;
    const hot = root.querySelector<HTMLStyleElement>("style[data-info-hot]")!;
    const show = (id: string | null) => {
      hot.textContent = id
        ? `#arena-spells [data-info]:not([data-info="${CSS.escape(id)}"]) { visibility: hidden; animation: none; } #arena-spells [data-info="${CSS.escape(id)}"] { visibility: visible; }`
        : "";
    };
    const spellAt = (node: EventTarget | null) =>
      node instanceof Element ? node.closest<HTMLElement>("#arena-spells [data-card]") : null;

    // Heading down to the trait tags under the tray, a slot crossed on the way only takes
    // over the pane if the pointer rests on it, so the tags of the spell you meant stay put.
    let dx = 0;
    let dy = 0;
    let aim: number | undefined;
    const onMove = (event: PointerEvent) => {
      dx = event.movementX;
      dy = event.movementY;
    };
    const onPoint = (event: Event) => {
      window.clearTimeout(aim);
      const spell = spellAt(event.target);
      if (!spell) return;
      const id = spell.dataset.card!;
      if (event.type === "pointerover" && dy > 1 && dy > Math.abs(dx)) {
        aim = window.setTimeout(() => spell.matches(":hover") && show(id), 150);
      } else show(id);
    };
    const onOut = (event: PointerEvent) => {
      const to = event.relatedTarget;
      if (!(to instanceof Element && to.closest("#arena-spells"))) {
        window.clearTimeout(aim);
        show(null);
      }
    };
    // Picking a spell closes the panel; next time it opens on the new selection.
    const onClick = (event: MouseEvent) => {
      if (spellAt(event.target)) {
        window.clearTimeout(aim);
        show(null);
      }
    };

    root.addEventListener("pointermove", onMove);
    root.addEventListener("pointerover", onPoint);
    root.addEventListener("focusin", onPoint);
    root.addEventListener("pointerout", onOut);
    root.addEventListener("click", onClick);
  },
};
