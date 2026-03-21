type SoundKey = "join" | "correct" | "gameMusic" | "wrongGuess" | "correctGuess" | "otherPlayerCorrect" | "countdown";

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
  mounted(this: any) {
    this.sounds = {} as Record<SoundKey, HTMLAudioElement>;

    const keys = ["join", "correct", "gameMusic", "wrongGuess", "correctGuess", "otherPlayerCorrect", "countdown"] as SoundKey[];
    for (const key of keys) {
      const audio = new Audio(SOUND_FILES[key]);
      audio.preload = "auto";
      this.sounds[key] = audio;
    }

    window.addEventListener("flamingo:mute", () => {
      for (const key of Object.keys(this.sounds)) {
        const audio = this.sounds[key as SoundKey] as HTMLAudioElement;
        audio.pause();
        audio.currentTime = 0;
        audio.loop = false;
      }
    });

    this.handleEvent("play_sound", ({ sound }: { sound: SoundKey }) => {
      if ((window as any).__soundMuted) return;
      const audio = this.sounds[sound];
      if (!audio) return;

      audio.currentTime = 0;
      audio.play().catch(() => {});
    });

    this.handleEvent("start_music", ({ sound }: { sound: SoundKey }) => {
      if ((window as any).__soundMuted) return;
      const audio = this.sounds[sound];
      if (!audio) return;

      audio.loop = true;
      if (!audio.paused) return;
      audio.play().catch(() => {});
    });

    this.handleEvent("stop_music", ({ sound }: { sound: SoundKey }) => {
      const audio = this.sounds[sound];
      if (!audio) return;

      audio.pause();
      audio.currentTime = 0;
      audio.loop = false;
    });

    this.handleEvent("start_countdown", () => {
      if ((window as any).__soundMuted) return;
      const audio = this.sounds.countdown;
      if (!audio) return;

      audio.currentTime = 0;
      audio.play().catch(() => {});
    });

    this.handleEvent("stop_countdown", () => {
      const audio = this.sounds.countdown;
      if (!audio) return;

      audio.pause();
      audio.currentTime = 0;
    });
  },
};

export default SoundManager;
