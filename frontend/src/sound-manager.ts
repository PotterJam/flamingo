import correctTone from './assets/sounds/correct-tone.wav';
import joinTone from './assets/sounds/retro-join.wav';

export const SOUNDS = {
    correct: correctTone,
    join: joinTone,
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

    return { loadSounds, playSound };
}

export const soundManager = createSoundManager();
