type SoundKey = "join" | "correct" | "gameMusic" | "wrongGuess" | "correctGuess" | "otherPlayerCorrect" | "countdown";

import type { GamePhase } from "../game_model";

interface SoundManagerHook {
  sounds: Record<SoundKey, HTMLAudioElement>;
  fadeTimers: Partial<Record<SoundKey, number>>;
  countdownTimer: number | null;
  countdownTurnEndTime: string | null;
  stopAllAudio?: () => void;
  handleEvent: <T>(event: string, callback: (payload: T) => void) => void;
}

const SOUND_FILES: Record<SoundKey, string> = {
  join: "/sounds/retro-join.wav",
  correct: "/sounds/correct-tone.wav",
  gameMusic: "/sounds/game-music.mp3",
  wrongGuess: "/sounds/wrong-guess.mp3",
  correctGuess: "/sounds/correct-guess.mp3",
  otherPlayerCorrect: "/sounds/other-player-correct.mp3",
  countdown: "/sounds/countdown.mp3",
};

const SoundManager = {
  mounted(this: SoundManagerHook) {
    this.sounds = {} as Record<SoundKey, HTMLAudioElement>;
    this.fadeTimers = {} as Partial<Record<SoundKey, number>>;
    this.countdownTimer = null as number | null;
    this.countdownTurnEndTime = null as number | null;

    const clearFade = (sound: SoundKey) => {
      const timer = this.fadeTimers[sound];
      if (timer !== undefined) {
        window.clearInterval(timer);
        delete this.fadeTimers[sound];
      }
    };

    const stopCountdown = () => {
      if (this.countdownTimer !== null) {
        window.clearTimeout(this.countdownTimer);
        this.countdownTimer = null;
      }

      this.countdownTurnEndTime = null;
      const audio = this.sounds.countdown;
      if (!audio) return;

      audio.pause();
      audio.currentTime = 0;
    };

    const fadeInMusic = () => {
      if (window.__soundMuted) return;
      const audio = this.sounds.gameMusic;
      if (!audio) return;

      clearFade("gameMusic");
      audio.loop = true;

      if (audio.paused) {
        audio.volume = 0;
        audio.play().catch(() => {});
      }

      this.fadeTimers.gameMusic = window.setInterval(() => {
        audio.volume = Math.min(0.08, audio.volume + 0.01);
        if (audio.volume >= 0.08) {
          clearFade("gameMusic");
        }
      }, 80);
    };

    const fadeOutMusic = () => {
      const audio = this.sounds.gameMusic;
      if (!audio) return;

      clearFade("gameMusic");
      if (audio.paused) return;

      this.fadeTimers.gameMusic = window.setInterval(() => {
        audio.volume = Math.max(0, audio.volume - 0.01);
        if (audio.volume <= 0) {
          clearFade("gameMusic");
          audio.pause();
          audio.currentTime = 0;
          audio.loop = false;
        }
      }, 80);
    };

    const startCountdown = () => {
      if (window.__soundMuted) return;
      const audio = this.sounds.countdown;
      if (!audio || !audio.paused) return;

      audio.currentTime = 0;
      audio.volume = 0.7;
      audio.play().catch(() => {});
    };

    const scheduleCountdown = (endTime: string) => {
      if (this.countdownTurnEndTime === endTime) return;

      stopCountdown();
      this.countdownTurnEndTime = endTime;

      const countdownStartDelay = new Date(endTime).getTime() - Date.now() - 10_000;
      if (countdownStartDelay <= 0) {
        startCountdown();
        return;
      }

      this.countdownTimer = window.setTimeout(() => {
        this.countdownTimer = null;
        if (this.countdownTurnEndTime === endTime) {
          startCountdown();
        }
      }, countdownStartDelay);
    };

    const syncRoundAudio = ({ phase, end_time }: { phase: GamePhase; end_time?: string | null }) => {
      if (phase === "playing" && end_time) {
        fadeInMusic();
        scheduleCountdown(end_time);
        return;
      }

      fadeOutMusic();
      stopCountdown();
    };

    const keys = ["join", "correct", "gameMusic", "wrongGuess", "correctGuess", "otherPlayerCorrect", "countdown"] as SoundKey[];
    for (const key of keys) {
      const audio = new Audio(SOUND_FILES[key]);
      audio.preload = "auto";
      this.sounds[key] = audio;
    }

    window.addEventListener("flamingo:mute", () => {
      if (this.countdownTimer !== null) {
        window.clearTimeout(this.countdownTimer);
        this.countdownTimer = null;
      }

      this.countdownTurnEndTime = null;

      for (const key of Object.keys(this.sounds)) {
        const audio = this.sounds[key as SoundKey] as HTMLAudioElement;
        clearFade(key as SoundKey);
        audio.pause();
        audio.currentTime = 0;
        audio.loop = false;
      }
    });

    this.handleEvent("play_sound", ({ sound }: { sound: SoundKey }) => {
      if (window.__soundMuted) return;
      const audio = this.sounds[sound];
      if (!audio) return;

      audio.currentTime = 0;
      audio.play().catch(() => {});
    });

    this.handleEvent("start_music", ({ sound }: { sound: SoundKey }) => {
      if (window.__soundMuted) return;
      const audio = this.sounds[sound];
      if (!audio) return;

      clearFade(sound);
      audio.loop = true;
      audio.currentTime = 0;
      audio.play().catch(() => {});
    });

    this.handleEvent("stop_music", ({ sound }: { sound: SoundKey }) => {
      const audio = this.sounds[sound];
      if (!audio) return;

      clearFade(sound);
      audio.pause();
      audio.currentTime = 0;
      audio.loop = false;
    });

    this.handleEvent("start_countdown", () => {
      startCountdown();
    });

    this.handleEvent("stop_countdown", () => {
      stopCountdown();
    });

    this.handleEvent("sync_round_audio", syncRoundAudio);

    this.stopAllAudio = () => {
      syncRoundAudio({ phase: "lobby" });
    };
  },

  destroyed(this: SoundManagerHook) {
    if (this.stopAllAudio) {
      this.stopAllAudio();
    }
  },
};

export default SoundManager;
