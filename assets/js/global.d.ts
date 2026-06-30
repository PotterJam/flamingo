export {};

declare global {
  interface Window {
    __soundMuted: boolean;
    __soundVolume: number;
  }
}
