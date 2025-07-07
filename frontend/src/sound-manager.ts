import correctTone from './assets/sounds/correct-tone.wav';
import joinTone from './assets/sounds/retro-join.wav';
import gameMusic from './assets/sounds/game-music.mp3';

export const SOUNDS = {
    correct: correctTone,
    join: joinTone,
    gameMusic: gameMusic,
} as const;

export type SoundName = keyof typeof SOUNDS;

function createSoundManager() {
    const sounds: Record<string, HTMLAudioElement> = {};

    const loadSounds = () => {
        for (const [name, url] of Object.entries(SOUNDS)) {
            sounds[name] = new Audio(url);
            sounds[name].preload = 'auto';
        }
    };

    const playSound = (name: SoundName) => {
        const sound = sounds[name];
        sound.currentTime = 0;
        sound.play();
    };

    const startOrContinueMusic = () => {
        const sound = sounds[gameMusic];
        if (sound.paused) {
            sound.loop = true;
            sound.volume = 0.2;
            sound.play();
        }
    };

    const stopMusic = () => {
        const sound = sounds[gameMusic];
        sound.pause;
    };

    return { loadSounds, playSound, startOrContinueMusic, stopMusic };
}

export const soundManager = createSoundManager();
