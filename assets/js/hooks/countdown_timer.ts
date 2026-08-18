type TimerPayload = { end_time?: string | null };

interface CountdownTimerHook {
  el: HTMLElement;
  timeout?: number;
  endTime?: string | null;
  handleVisibilityChange: () => void;
  startTimer: (endTime?: string | null) => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
}

const CountdownTimer = {
  mounted(this: CountdownTimerHook) {
    this.startTimer = (endTime) => {
      window.clearTimeout(this.timeout);
      this.endTime = endTime;
      const end = endTime ? new Date(endTime).getTime() : NaN;

      if (!Number.isFinite(end)) {
        this.el.textContent = "--";
        return;
      }

      const update = () => {
        const seconds = Math.max(0, Math.ceil((end - Date.now()) / 1000));
        this.el.textContent = String(seconds).padStart(2, "0");

        if (seconds > 0) this.timeout = window.setTimeout(update, 250);
      };

      update();
    };

    this.handleVisibilityChange = () => {
      if (!document.hidden) this.startTimer(this.endTime);
    };

    document.addEventListener("visibilitychange", this.handleVisibilityChange);
    this.startTimer(this.el.dataset.endTime);
    this.handleEvent<TimerPayload>("set_timer", ({ end_time }) => this.startTimer(end_time));
  },

  destroyed(this: CountdownTimerHook) {
    window.clearTimeout(this.timeout);
    document.removeEventListener("visibilitychange", this.handleVisibilityChange);
  },
};

export default CountdownTimer;
