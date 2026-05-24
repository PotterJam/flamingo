interface FinalDrawingShowcaseHook {
  el: HTMLElement;
  selectedPlayerId?: string;
  replayFinalDrawings: () => void;
  replay: () => void;
}

const FinalDrawingShowcase = {
  mounted(this: FinalDrawingShowcaseHook) {
    this.selectedPlayerId = this.el.dataset.selectedPlayerId;
    this.replayFinalDrawings = () => {
      window.dispatchEvent(new Event("flamingo:replay-final-drawings"));
    };

    this.el.addEventListener("click", (event: MouseEvent) => {
      if ((event.target as HTMLElement).closest("[data-replay-final-drawings]")) {
        this.replay();
      }
    });

    this.replay();
  },

  updated(this: FinalDrawingShowcaseHook) {
    const selectedPlayerId = this.el.dataset.selectedPlayerId;

    if (selectedPlayerId !== this.selectedPlayerId) {
      this.selectedPlayerId = selectedPlayerId;
      this.replay();
    }
  },

  replay(this: FinalDrawingShowcaseHook) {
    window.setTimeout(this.replayFinalDrawings, 0);
  },
};

export default FinalDrawingShowcase;
