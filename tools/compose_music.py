"""Compose the game's chiptune set — three NES-style loops, rendered straight to PCM16 WAV with numpy.

Every track shares one synth stack (25%-ish duty square lead with vibrato + single-tap echo,
16th-note square arpeggio, triangle walking bass, synthesized drums: swept-sine kick, band-noise
snare, hiss hats) so the set feels like one cabinet of cartridges. They differ in tempo, key
(global semitone transpose of the E-minor chord system), progression, melody-rhythm plans, arp
cycle, lead duty and seed — cohesive, never repetitive.

24 bars of 4/4 per song; each ends on the B7 turnaround so the WAV-to-WAV restart lands like a
repeat sign. All deterministic (seeded rng): re-running regenerates the exact same files.
    python tools/compose_music.py
"""
import os
import wave
import numpy as np

SR = 44100
TAIL = 0.15   # small breath of silence at the loop seam

# (bass root MIDI, chord tones low octave for arps, pool near octave 5 for the lead) — the E-minor system
CHORDS = {
    "Em": (40, [52, 55, 59], [76, 79, 83]),
    "Am": (45, [45, 48, 52], [76, 72, 69]),
    "C":  (36, [48, 52, 55], [72, 76, 79]),
    "D":  (38, [50, 54, 57], [74, 78, 81]),
    "B7": (47, [47, 51, 54], [75, 78, 83]),
}
# melody rhythm templates: (eighth slot, length in eighths) — all hand-tested cadences
TEMPLATES = {
    1: [(0, 1), (2, 1), (4, 2), (6, 1)],
    2: [(0, 2), (3, 1), (4, 2), (6, 1)],
    3: [(0, 1), (2, 1), (3, 1), (4, 1), (6, 2)],
    4: [(0, 2), (3, 1), (4, 4)],
}


def midi_f(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def compose(name, bpm, seed, sections, sec_tpl, sec_idx, arp_cycle,
            transpose=0, lead_duty=0.25, echo=0.17, lead_amp=0.50, bars=24):
    beat = 60.0 / bpm
    bar = 4 * beat
    rng = np.random.default_rng(seed)

    n_total = int((bars * bar + TAIL) * SR)
    mix = np.zeros(n_total, np.float64)
    lead = np.zeros(n_total, np.float64)

    def add(buf, t0, y, gain):
        i0 = int(round(t0 * SR))
        if i0 >= len(buf):
            return
        seg = y[:len(buf) - i0]
        buf[i0:i0 + len(seg)] += seg * gain

    def envelope(n, a=0.005, dec=13.0, sus=0.72, rel=0.04):
        t = np.arange(n) / SR
        env = np.minimum(t / a, 1.0)
        env *= sus + (1.0 - sus) * np.exp(-np.maximum(t - a, 0.0) * dec)
        env *= np.clip((t[-1] - t) / rel, 0.0, 1.0)
        return env

    def tone(m, dur, kind="sq", amp=1.0, vib=0.0, duty=0.25):
        """One note: plucky envelope, mild vibrato for the lead, DC-free pulse for squares."""
        n = max(8, int(dur * SR))
        t = np.arange(n) / SR
        f = midi_f(m + transpose)
        if kind == "tri":
            ph = np.cumsum(np.full(n, f)) / SR
            y = (2.0 / np.pi) * np.arcsin(np.sin(2.0 * np.pi * ph))
        else:
            freq = f * (1.0 + vib * np.sin(2.0 * np.pi * 5.5 * t)) if vib else np.full(n, f)
            ph = np.cumsum(freq) / SR
            y = ((ph - np.floor(ph)) < duty) * 2.0 - 1.0
            y -= (2.0 * duty - 1.0)                     # remove the pulse's DC offset
        return y * envelope(n) * amp

    def kick():
        n = int(0.11 * SR)
        t = np.arange(n) / SR
        f = 45.0 + 55.0 * np.exp(-t * 38.0)
        y = np.sin(2.0 * np.pi * (np.cumsum(f) / SR)) * np.exp(-t * 26.0)
        y += rng.standard_normal(n) * np.exp(-t * 240.0) * 0.35     # beater click
        return y

    def snare():
        n = int(0.11 * SR)
        t = np.arange(n) / SR
        noise = rng.standard_normal(n)
        body = noise - np.convolve(noise, np.ones(5) / 5.0, "same")
        return body * np.exp(-t * 30.0) * 0.95 + noise * np.exp(-t * 58.0) * 0.22

    def hat(amp=1.0):
        n = int(0.05 * SR)
        t = np.arange(n) / SR
        noise = rng.standard_normal(n)
        hiss = noise - np.convolve(noise, np.ones(3) / 3.0, "same")
        return hiss * np.exp(-t * 85.0) * amp

    for b in range(bars):
        sec, row = b // 8, b % 8
        root, arp_low, pool = CHORDS[sections[sec][row]]
        t0 = b * bar
        oct_up = 12 if sec == 2 else 0

        # lead melody
        tpl = TEMPLATES[sec_tpl[sec][row]]
        idx_pat = sec_idx[(b + row) % 3]
        for k, (slot, ln) in enumerate(tpl):
            m = pool[idx_pat[k % len(idx_pat)] % 3] + (12 * (idx_pat[k % len(idx_pat)] // 3)) + oct_up
            if m > 86: m -= 12
            if m < 65: m += 12
            add(lead, t0 + slot * beat / 2.0, tone(m, ln * beat / 2.0 * 0.92, "sq", 1.0, vib=0.008, duty=lead_duty), 1.0)

        # arpeggio: one 16th per slot, quiet, short
        for s16 in range(32):
            m = arp_low[arp_cycle[s16 % 4]] + (12 if (s16 // 4) % 2 == 1 else 0)
            add(mix, t0 + s16 * beat / 4.0, tone(m, beat / 4.0 * 0.62, "sq", 1.0, duty=0.5), 0.20)

        # triangle walking bass: root, fifth, octave, fifth
        for bi, off in enumerate([0, 7, 12, 7]):
            add(mix, t0 + bi * beat, tone(root + off, beat * 0.8, "tri"), 0.40)

        # drums
        add(mix, t0 + 0 * beat, kick(), 0.46)
        add(mix, t0 + 2 * beat, kick(), 0.46)
        add(mix, t0 + 1 * beat, snare(), 0.36)
        add(mix, t0 + 3 * beat, snare(), 0.36)
        for slot in (1, 3, 5, 7):                                        # offbeat hats
            add(mix, t0 + slot * beat / 2.0, hat(0.10), 1.0)
        if sec >= 1:                                                      # busier pulse from section 2 on
            for slot in (0, 2, 4, 6):
                add(mix, t0 + slot * beat / 2.0, hat(0.05), 1.0)
        if row == 7:                                                      # end-of-section fill
            add(mix, t0 + 3.5 * beat, snare(), 0.30)
            add(mix, t0 + 3.75 * beat, snare(), 0.18)

    # single-tap echo on the lead (spares the other instruments the mud)
    echo_t = int(echo * SR)
    lead_mix = lead * lead_amp
    lead_mix[echo_t:] += lead[:-echo_t] * 0.14

    out = mix + lead_mix
    out = np.tanh(out * 1.25)
    out = out / np.max(np.abs(out)) * 0.86
    pcm = (out * 32767.0).astype(np.int16)

    out_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "music", name + ".wav")
    with wave.open(out_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print(name + ".wav", round(len(pcm) / SR, 1), "s,", os.path.getsize(out_path) // 1024, "KB")


SONGS = [
    # ---- 1. "Neon Corridor" — the original: E minor, driving 140 BPM (seed 42 reproduces it byte-exact)
    dict(name="neon_corridor", bpm=140.0, seed=42,
         sections=[["Em", "Em", "C", "D", "Em", "Em", "C", "B7"],     # A  — driving minor loop
                   ["Am", "Am", "C", "D", "Em", "Em", "C", "B7"],     # A' — lifts on the Aeolian VI/iv color
                   ["Em", "Em", "C", "D", "Am", "C", "D", "B7"]],     # A″ — build back to the turnaround
         sec_tpl=[[1, 2, 1, 3, 1, 2, 3, 4], [2, 3, 1, 2, 2, 3, 1, 4], [1, 3, 1, 3, 2, 3, 2, 4]],
         sec_idx=[[2, 1, 0, 1], [0, 2, 1, 2], [1, 0, 2, 1]],
         arp_cycle=[0, 1, 2, 1]),
    # ---- 2. "Starlight Patrol" — G minor, airy 128 BPM: a hymn-like i–♭VI–♭VII–VII7 march
    dict(name="starlight_patrol", bpm=128.0, seed=7, transpose=3,
         sections=[["Em", "C", "Am", "B7", "Em", "C", "D", "B7"],
                   ["Am", "C", "Em", "D", "Am", "C", "D", "B7"],
                   ["Em", "C", "D", "C", "Am", "Em", "D", "B7"]],
         sec_tpl=[[1, 2, 3, 2, 1, 3, 2, 4], [3, 1, 2, 3, 2, 1, 3, 4], [2, 1, 3, 2, 3, 1, 2, 4]],
         sec_idx=[[1, 2, 0, 2], [2, 0, 1, 0], [0, 1, 2, 1]],
         arp_cycle=[0, 2, 1, 2], echo=0.21),
    # ---- 3. "Circuit Sunset" — A minor, bright 152 BPM: thin buzzy lead, sprinting arps
    dict(name="circuit_sunset", bpm=152.0, seed=13, transpose=-5,
         sections=[["Em", "Am", "C", "Em", "D", "Em", "C", "B7"],
                   ["C", "D", "Em", "Em", "Am", "C", "D", "B7"],
                   ["Em", "D", "C", "Em", "Am", "D", "C", "B7"]],
         sec_tpl=[[1, 2, 1, 2, 3, 2, 1, 4], [2, 1, 3, 1, 2, 3, 2, 4], [1, 3, 2, 3, 1, 2, 3, 4]],
         sec_idx=[[0, 1, 2, 1], [1, 0, 2, 0], [2, 0, 1, 2]],
         arp_cycle=[0, 1, 2, 0], lead_duty=0.18, echo=0.13, lead_amp=0.44),
]

for song in SONGS:
    compose(**song)
