#!/usr/bin/env python3
"""
Generate ready.wav, the sound the robot plays once its startup checks pass.

Three soft sine notes rising (C5, E5, G5), each with a 20 ms attack, a long
exponential decay and a little second harmonic for warmth, overlapping so they
blend into one chord. Peak is -12 dBFS so it is never startling. Mono, 22050 Hz,
16-bit, about 1.3 s, well under 80 KB. Standard library only, deterministic:
running it again gives a byte-identical file.

    python3 make_ready_chime.py [out.wav]
"""
import math
import struct
import sys
import wave

RATE = 22050
DURATION_S = 1.3
PEAK_DBFS = -12.0
ATTACK_S = 0.020
FADE_OUT_S = 0.040
DECAY_TAU_S = 0.38
HARMONIC_LEVEL = 0.18
HARMONIC_TAU_S = 0.16
# (frequency Hz, onset s): C5, E5, G5
NOTES = ((523.25, 0.00), (659.25, 0.26), (783.99, 0.52))


def note_sample(t, freq, onset):
    """One note's amplitude at time t (0 before its onset)."""
    dt = t - onset
    if dt < 0.0:
        return 0.0
    if dt < ATTACK_S:
        env = 0.5 - 0.5 * math.cos(math.pi * dt / ATTACK_S)
    else:
        env = 1.0
    decay = math.exp(-dt / DECAY_TAU_S)
    harmonic = HARMONIC_LEVEL * math.exp(-dt / HARMONIC_TAU_S)
    phase = 2.0 * math.pi * freq * dt
    return env * decay * (math.sin(phase) + harmonic * math.sin(2.0 * phase))


def render():
    n = int(RATE * DURATION_S)
    samples = []
    for i in range(n):
        t = i / RATE
        v = sum(note_sample(t, f, on) for f, on in NOTES)
        remaining = (n - 1 - i) / RATE
        if remaining < FADE_OUT_S:
            v *= remaining / FADE_OUT_S
        samples.append(v)
    peak = max(abs(v) for v in samples)
    target = 10.0 ** (PEAK_DBFS / 20.0) * 32767.0
    gain = target / peak
    pcm = [int(round(v * gain)) for v in samples]
    pcm[0] = 0
    pcm[-1] = 0
    return pcm


def write(path, pcm):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack('<%dh' % len(pcm), *pcm))


def main(argv):
    out = argv[1] if len(argv) > 1 else 'ready.wav'
    pcm = render()
    write(out, pcm)
    peak = max(abs(v) for v in pcm)
    print('%s: %d samples, %.2f s, peak %.1f dBFS' % (
        out, len(pcm), len(pcm) / RATE, 20.0 * math.log10(peak / 32767.0)))


if __name__ == '__main__':
    main(sys.argv)
