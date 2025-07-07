import correctTone from './assets/sounds/correct-tone.wav';
import joinTone from './assets/sounds/retro-join.wav';
import gameMusicTrack from './assets/sounds/game-music.mp3';
import wrongGuessTone from './assets/sounds/wrong-guess.mp3';
import correctGuessTone from './assets/sounds/correct-guess.mp3';
import otherPlayerCorrectTone from './assets/sounds/other-player-correct.mp3';
import countdownTone from './assets/sounds/countdown.mp3';

export const SOUNDS = {
    correct: correctTone,
    join: joinTone,
    gameMusic: gameMusicTrack,
    wrongGuess: wrongGuessTone,
    correctGuess: correctGuessTone,
    otherPlayerCorrect: otherPlayerCorrectTone,
    countdown: countdownTone,
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
        const sound = sounds['gameMusic'];
        if (sound.paused) {
            sound.loop = true;
            sound.volume = 0.08;
            sound.play();
        }
    };

    const stopMusic = () => {
        const sound = sounds['gameMusic'];
        sound.pause();
    };

    const startOrContinueCountdown = () => {
        const sound = sounds['countdown'];
        if (sound.paused) {
            sound.volume = 0.7;
            sound.play();
        }
    };

    const stopCountdown = () => {
        const sound = sounds['countdown'];
        sound.pause();
    };

    return { loadSounds, playSound, startOrContinueMusic, stopMusic, startOrContinueCountdown, stopCountdown };
}

export const soundManager = createSoundManager();
