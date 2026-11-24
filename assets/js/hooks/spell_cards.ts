// The spell panel works like Worms' weapon panel: pointing at a spell shows its picture
// and numbers in the pane beside the grid at once, with no wait; away from the grid the
// pane goes back to the spell you have selected. The server renders every spell's pane
// and shows the selected one; all the panes share one grid cell, so the pane is always
// the tallest one's size and the panel never jumps. This hook only overrides which pane
// is visible, through a style rule in an ignored element, so LiveView patches keep it.

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

    const onPoint = (event: Event) => {
      const spell = spellAt(event.target);
      if (spell) show(spell.dataset.card!);
    };
    const onOut = (event: PointerEvent) => {
      const to = event.relatedTarget;
      if (!(to instanceof Element && to.closest("#arena-spells"))) show(null);
    };
    // Picking a spell closes the panel; next time it opens on the new selection.
    const onClick = (event: MouseEvent) => {
      if (spellAt(event.target)) show(null);
    };

    root.addEventListener("pointerover", onPoint);
    root.addEventListener("focusin", onPoint);
    root.addEventListener("pointerout", onOut);
    root.addEventListener("click", onClick);
  },
};
