// Spellslingers sound effects, synthesized with the Web Audio API so there are no files
// to load. Each spell belongs to a school that gives its charge, launch and impact one
// character: fire roars and crackles, earth rumbles, storm zaps, nature chimes, and
// arcane shimmers. Every sound follows the site-wide volume and is silent at zero.

type School = "fire" | "earth" | "storm" | "nature" | "arcane";

const SCHOOLS: Record<string, School> = {
  ember: "fire", inferno: "fire", firerain: "fire", surge: "fire",
  boulder: "earth", rampart: "earth", golem: "earth", quake: "earth", burrow: "earth", ledge: "earth",
  lance: "storm", gust: "storm", chain: "storm", updraft: "storm",
  bloom: "nature", thornling: "nature", wisp: "nature",
};

const schoolOf = (spell: string) => SCHOOLS[spell] ?? "arcane";

// Spells that land with an explosion; the rest have their own landing sound or none.
const EXPLODES = new Set(["ember", "inferno", "boulder", "lance", "cluster", "firerain", "surge", "chain", "chaos"]);
const SUMMONS = new Set(["imp", "golem", "wisp", "thornling"]);
// Meteors: wild-magic surges and the falling half of Meteor Rain.
const METEORS = new Set(["firerain", "surge"]);

type Segment = { path: unknown[]; start: number; spell: string; radius: number; hit: boolean };
type Cast = { spell: string; segments: Segment[]; auras?: { kind: string }[] };

// The charge hum: oscillators that rise through a filter, with a noise layer on top.
const CHARGE: Record<School, { wave: OscillatorType; from: number; to: number; open: [number, number]; noise: [BiquadFilterType, number, number] }> = {
  fire: { wave: "sawtooth", from: 110, to: 330, open: [500, 2600], noise: ["bandpass", 700, 2600] },
  earth: { wave: "square", from: 55, to: 150, open: [260, 900], noise: ["lowpass", 180, 600] },
  storm: { wave: "sawtooth", from: 220, to: 880, open: [1200, 5000], noise: ["highpass", 3000, 7000] },
  nature: { wave: "triangle", from: 262, to: 784, open: [1800, 4000], noise: ["bandpass", 2000, 4500] },
  arcane: { wave: "sine", from: 330, to: 990, open: [3000, 6000], noise: ["bandpass", 3000, 8000] },
};

type ToneOptions = { wave?: OscillatorType; from: number; to?: number; dur: number; gain: number; at?: number; attack?: number; vibrato?: number };
type HissOptions = { filter?: BiquadFilterType; from: number; to?: number; q?: number; dur: number; gain: number; at?: number; attack?: number };

export function createSpellSounds(volume: () => number, makeContext: () => BaseAudioContext = () => new AudioContext()) {
  let ctx: BaseAudioContext | null = null;
  let bus: GainNode;
  let noise: AudioBuffer;

  // The context starts on first use; a browser that suspended it until a gesture is asked again each time.
  const ready = () => {
    if (volume() <= 0) return null;
    if (!ctx) {
      ctx = makeContext();
      bus = ctx.createGain();
      // Overlapping blasts are squeezed rather than clipped.
      const limiter = ctx.createDynamicsCompressor();
      limiter.threshold.value = -10;
      limiter.ratio.value = 8;
      bus.connect(limiter).connect(ctx.destination);
      noise = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
      const data = noise.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    }
    if (ctx.state === "suspended" && "resume" in ctx) (ctx as AudioContext).resume().catch(() => {});
    bus.gain.setValueAtTime(volume(), ctx.currentTime);
    return ctx;
  };

  // A gain that swells in over `attack` and dies away by `end`.
  const envelope = (c: BaseAudioContext, t0: number, attack: number, peak: number, end: number) => {
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(peak, t0 + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, end);
    g.connect(bus);
    return g;
  };

  const tone = ({ wave = "sine", from, to, dur, gain, at = 0, attack = 0.005, vibrato }: ToneOptions) => {
    const c = ready();
    if (!c) return;
    const t0 = c.currentTime + at;
    const osc = c.createOscillator();
    osc.type = wave;
    osc.frequency.setValueAtTime(from, t0);
    if (to) osc.frequency.exponentialRampToValueAtTime(to, t0 + dur);
    if (vibrato) {
      const lfo = c.createOscillator();
      const depth = c.createGain();
      lfo.frequency.value = vibrato;
      depth.gain.value = from * 0.04;
      lfo.connect(depth).connect(osc.frequency);
      lfo.start(t0);
      lfo.stop(t0 + dur + 0.05);
    }
    osc.connect(envelope(c, t0, attack, gain, t0 + dur));
    osc.start(t0);
    osc.stop(t0 + dur + 0.05);
  };

  const hiss = ({ filter = "lowpass", from, to, q = 1, dur, gain, at = 0, attack = 0.005 }: HissOptions) => {
    const c = ready();
    if (!c) return;
    const t0 = c.currentTime + at;
    const source = c.createBufferSource();
    source.buffer = noise;
    source.loop = true;
    const f = c.createBiquadFilter();
    f.type = filter;
    f.Q.value = q;
    f.frequency.setValueAtTime(from, t0);
    if (to) f.frequency.exponentialRampToValueAtTime(to, t0 + dur);
    source.connect(f).connect(envelope(c, t0, attack, gain, t0 + dur));
    source.start(t0, Math.random() * 1.5);
    source.stop(t0 + dur + 0.05);
  };

  const explosion = (spell: string, radius: number) => {
    const meteor = METEORS.has(spell);
    const k = Math.min(1, (radius + (meteor ? 4 : 0)) / 10);
    hiss({ from: 1800 + k * 1500, to: 60, dur: 0.5 + k * 0.9, gain: 0.45 + k * 0.45 });
    tone({ from: 130, to: 32, dur: 0.4 + k * 0.6, gain: 0.5 + k * 0.4 });
    const school = schoolOf(spell);
    if (school === "fire") hiss({ filter: "highpass", from: 3500, dur: 0.6, gain: 0.12, at: 0.05, attack: 0.05 });
    if (school === "storm") tone({ wave: "sawtooth", from: 1800, to: 180, dur: 0.18, gain: 0.12 });
    if (school === "earth") for (const at of [0.12, 0.24, 0.38]) hiss({ from: 900, to: 300, dur: 0.12, gain: 0.18, at });
  };

  const chime = (notes: number[], gap: number, gain = 0.12, wave: OscillatorType = "triangle") =>
    notes.forEach((note, i) => tone({ wave, from: note, dur: 0.5, gain, at: i * gap, attack: 0.01 }));

  const teleport = () => {
    tone({ from: 300, to: 1800, dur: 0.4, gain: 0.25, vibrato: 18 });
    tone({ wave: "triangle", from: 1200, to: 2400, dur: 0.3, gain: 0.1, at: 0.08 });
    hiss({ filter: "bandpass", from: 1500, to: 7000, q: 2, dur: 0.45, gain: 0.35 });
  };

  const rumble = (dur: number, gain: number) => {
    hiss({ from: 170, to: 60, dur, gain, attack: 0.3 });
    tone({ wave: "triangle", from: 46, to: 30, dur, gain: gain * 0.45, attack: 0.25, vibrato: 7 });
  };

  return {
    // Rises over `ms`, the time a charge takes to reach full power, then holds there.
    // Returns the function that stops it.
    charge(spell: string, ms: number) {
      const c = ready();
      if (!c) return () => {};
      const voice = CHARGE[schoolOf(spell)];
      const t0 = c.currentTime;
      const full = t0 + ms / 1000;
      const out = c.createGain();
      out.gain.setValueAtTime(0.0001, t0);
      out.gain.exponentialRampToValueAtTime(1, t0 + 0.08);
      out.connect(bus);

      const filter = c.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.setValueAtTime(voice.open[0], t0);
      filter.frequency.exponentialRampToValueAtTime(voice.open[1], full);
      const amp = c.createGain();
      amp.gain.setValueAtTime(0.035, t0);
      amp.gain.linearRampToValueAtTime(0.07, full);
      filter.connect(amp).connect(out);

      // A tremolo that speeds up as the power builds.
      const tremolo = c.createOscillator();
      const depth = c.createGain();
      tremolo.frequency.setValueAtTime(5, t0);
      tremolo.frequency.linearRampToValueAtTime(16, full);
      depth.gain.value = 0.025;
      tremolo.connect(depth).connect(amp.gain);

      const sources: AudioScheduledSourceNode[] = [tremolo];
      for (const [ratio, level] of [[1, 1], [1.5, 0.5], [1.006, 0.6]]) {
        const osc = c.createOscillator();
        osc.type = voice.wave;
        osc.frequency.setValueAtTime(voice.from * ratio, t0);
        osc.frequency.linearRampToValueAtTime(voice.to * ratio, full);
        const g = c.createGain();
        g.gain.value = level;
        osc.connect(g).connect(filter);
        sources.push(osc);
      }

      const air = c.createBufferSource();
      air.buffer = noise;
      air.loop = true;
      const airFilter = c.createBiquadFilter();
      airFilter.type = voice.noise[0];
      airFilter.frequency.setValueAtTime(voice.noise[1], t0);
      airFilter.frequency.exponentialRampToValueAtTime(voice.noise[2], full);
      const airGain = c.createGain();
      airGain.gain.setValueAtTime(0.03, t0);
      airGain.gain.linearRampToValueAtTime(0.08, full);
      air.connect(airFilter).connect(airGain).connect(out);
      sources.push(air);

      for (const source of sources) source.start(t0);
      let stopped = false;
      return () => {
        if (stopped || !ctx) return;
        stopped = true;
        const t = ctx.currentTime;
        out.gain.cancelScheduledValues(t);
        out.gain.setTargetAtTime(0, t, 0.03);
        for (const source of sources) source.stop(t + 0.2);
      };
    },

    // A cast starting to play: its launch, and the whistle of any meteors falling later.
    cast(cast: Cast, msPerStep: number) {
      const { spell } = cast;
      if (spell === "quake") {
        rumble(2.8, 1);
        for (const at of [0.35, 0.9, 1.5]) hiss({ filter: "bandpass", from: 1600, to: 250, q: 0.8, dur: 0.22, gain: 0.4, at });
      } else if (spell === "gust") {
        hiss({ filter: "bandpass", from: 300, to: 1800, q: 1.2, dur: 0.9, gain: 1, attack: 0.15 });
      } else if (spell === "updraft") {
        hiss({ filter: "bandpass", from: 400, to: 2600, q: 1.2, dur: 0.8, gain: 0.8, attack: 0.2 });
        tone({ from: 300, to: 900, dur: 0.6, gain: 0.07, attack: 0.1 });
      } else if (spell === "burrow") {
        tone({ wave: "sawtooth", from: 70, to: 95, dur: 0.9, gain: 0.12, vibrato: 28 });
        hiss({ from: 500, to: 250, dur: 0.9, gain: 0.3 });
      } else if (spell === "lance" || spell === "chain") {
        tone({ wave: "sawtooth", from: 2000, to: 300, dur: 0.28, gain: 0.13 });
        hiss({ filter: "highpass", from: 4000, to: 1500, dur: 0.25, gain: 0.2 });
      } else if (spell !== "surge") {
        const school = schoolOf(spell);
        if (school === "fire") {
          hiss({ from: 2800, to: 350, dur: 0.55, gain: 0.6, attack: 0.02 });
          tone({ from: 190, to: 60, dur: 0.2, gain: 0.25 });
        } else if (school === "earth") {
          tone({ from: 150, to: 50, dur: 0.25, gain: 0.35 });
          hiss({ from: 700, to: 150, dur: 0.3, gain: 0.25 });
        } else if (school === "nature") {
          chime([523, 784], 0.08, 0.1);
          hiss({ filter: "bandpass", from: 3000, q: 2, dur: 0.25, gain: 0.08 });
        } else {
          tone({ from: 400, to: 1200, dur: 0.3, gain: 0.12, vibrato: 12 });
          tone({ wave: "triangle", from: 800, to: 2400, dur: 0.25, gain: 0.05, at: 0.05 });
          hiss({ filter: "highpass", from: 5000, dur: 0.3, gain: 0.06 });
        }
      }

      for (const segment of cast.segments) {
        if (!METEORS.has(segment.spell) || (segment.start === 0 && spell !== "surge")) continue;
        const dur = Math.max(0.2, ((segment.path.length - 1) * msPerStep) / 1000);
        const at = (segment.start * msPerStep) / 1000;
        tone({ from: 1500, to: 380, dur, gain: 0.06, at, attack: 0.1 });
        hiss({ filter: "bandpass", from: 2500, to: 600, q: 3, dur, gain: 0.1, at, attack: 0.1 });
      }
    },

    // One flight ending: a blast, a landing, or a fizzle where it fell out of the world.
    land(segment: Segment) {
      const { spell, hit, radius } = segment;
      if (!hit) {
        hiss({ filter: "bandpass", from: 1600, to: 350, q: 1.5, dur: 0.45, gain: 0.6 });
        tone({ from: 700, to: 220, dur: 0.18, gain: 0.16 });
      } else if (EXPLODES.has(spell)) {
        explosion(spell, radius);
      } else if (spell === "rampart") {
        rumble(0.8, 0.6);
        tone({ from: 90, to: 160, dur: 0.6, gain: 0.2, attack: 0.1 });
      } else if (spell === "ledge") {
        tone({ from: 200, to: 90, dur: 0.15, gain: 0.35 });
        hiss({ from: 900, to: 200, dur: 0.15, gain: 0.25 });
      } else if (spell === "bloom") {
        chime([523, 659, 784, 1047], 0.07, 0.09, "sine");
        hiss({ filter: "highpass", from: 6000, dur: 0.5, gain: 0.05, attack: 0.1 });
      } else if (spell === "gust" || spell === "updraft") {
        hiss({ filter: "bandpass", from: 1200, to: 300, q: 1, dur: 0.6, gain: 0.7 });
      } else if (SUMMONS.has(spell)) {
        // A puff of smoke; the minion's arrival chime plays when it appears on the board.
        hiss({ filter: "bandpass", from: 1400, to: 300, q: 1, dur: 0.35, gain: 0.3 });
      }
    },

    // Lightning arcing to the next target.
    zap() {
      for (let i = 0; i < 6; i++) hiss({ filter: "highpass", from: 2500 + Math.random() * 3000, dur: 0.05, gain: 0.15, at: i * 0.07 });
      tone({ wave: "square", from: 110, to: 90, dur: 0.45, gain: 0.07, vibrato: 50 });
    },

    // A wizard knocked out, as they land or sink.
    knockout() {
      explosion("inferno", 14);
      tone({ wave: "sawtooth", from: 420, to: 110, dur: 1.1, gain: 0.07, at: 0.15, vibrato: 6 });
    },

    // What happens once the flights end: auras appearing.
    aftermath(cast: Cast) {
      for (const aura of cast.auras ?? []) {
        if (aura.kind === "ward") chime([880, 1320, 1760], 0.05, 0.08, "sine");
        else if (aura.kind === "levitate") {
          hiss({ filter: "bandpass", from: 500, to: 2500, q: 1.5, dur: 0.7, gain: 0.5, attack: 0.15 });
          tone({ from: 400, to: 1000, dur: 0.6, gain: 0.07, attack: 0.1 });
        }
      }
    },

    teleport,

    // A wizard pushing off for a jump, and its feet touching down again.
    jump() {
      tone({ wave: "triangle", from: 220, to: 520, dur: 0.18, gain: 0.18 });
      hiss({ filter: "bandpass", from: 600, to: 1800, q: 1, dur: 0.25, gain: 0.25 });
    },
    landed() {
      tone({ from: 140, to: 70, dur: 0.12, gain: 0.25 });
      hiss({ from: 700, to: 200, dur: 0.12, gain: 0.3 });
    },

    // Health changing on the board, from spells, minions, falls or crates.
    hurt(amount: number) {
      const k = Math.min(1, amount / 40);
      tone({ wave: "square", from: 260 - k * 80, to: 110 - k * 30, dur: 0.18 + k * 0.12, gain: 0.12 + k * 0.08 });
      hiss({ filter: "bandpass", from: 900, q: 1, dur: 0.12, gain: 0.6 });
    },
    heal: () => chime([659, 880, 1175], 0.06, 0.07, "sine"),
    blocked() {
      tone({ from: 523, dur: 0.5, gain: 0.12 });
      tone({ from: 1390, dur: 0.35, gain: 0.07 });
      hiss({ filter: "highpass", from: 3000, dur: 0.05, gain: 0.25 });
    },
    summoned: () => chime([392, 523, 659], 0.06, 0.08),

    close() {
      if (ctx && "close" in ctx) (ctx as AudioContext).close().catch(() => {});
      ctx = null;
    },
  };
}
