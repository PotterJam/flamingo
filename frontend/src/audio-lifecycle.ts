import { GamePhase } from './model';

export interface RoundAudioControls {
    fadeInMusic: () => void;
    fadeOutMusic: () => void;
    startOrContinueCountdown: () => void;
    stopCountdown: () => void;
}

export interface RoundAudioTimers {
    now: () => number;
    setTimeout: (handler: () => void, timeout: number) => number;
    clearTimeout: (timerId: number) => void;
}

export interface RoundAudioLifecycle {
    sync: (phase: GamePhase, turnEndTime: number | null) => void;
    stopAll: () => void;
}

const COUNTDOWN_SECONDS = 10;
const COUNTDOWN_MS = COUNTDOWN_SECONDS * 1000;

export const createRoundAudioLifecycle = (
    controls: RoundAudioControls,
    timers: RoundAudioTimers = {
        now: () => Date.now(),
        setTimeout: (handler, timeout) => window.setTimeout(handler, timeout),
        clearTimeout: (timerId) => window.clearTimeout(timerId),
    }
): RoundAudioLifecycle => {
    let countdownTimer: number | null = null;
    let countdownTurnEndTime: number | null = null;

    const clearCountdownTimer = () => {
        if (countdownTimer !== null) {
            timers.clearTimeout(countdownTimer);
            countdownTimer = null;
        }
    };

    const stopCountdown = () => {
        clearCountdownTimer();
        countdownTurnEndTime = null;
        controls.stopCountdown();
    };

    const scheduleCountdown = (turnEndTime: number) => {
        if (countdownTurnEndTime === turnEndTime) {
            return;
        }

        stopCountdown();
        countdownTurnEndTime = turnEndTime;

        const countdownStartDelay = turnEndTime - timers.now() - COUNTDOWN_MS;
        if (countdownStartDelay <= 0) {
            controls.startOrContinueCountdown();
            return;
        }

        countdownTimer = timers.setTimeout(() => {
            countdownTimer = null;
            if (countdownTurnEndTime === turnEndTime) {
                controls.startOrContinueCountdown();
            }
        }, countdownStartDelay);
    };

    const sync = (phase: GamePhase, turnEndTime: number | null) => {
        if (phase !== 'Guessing' || turnEndTime === null) {
            controls.fadeOutMusic();
            stopCountdown();
            return;
        }

        controls.fadeInMusic();
        scheduleCountdown(turnEndTime);
    };

    const stopAll = () => {
        controls.fadeOutMusic();
        stopCountdown();
    };

    return { sync, stopAll };
};
