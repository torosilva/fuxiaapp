"""Fuxia Kids · original music-box waltz (3/4, D major), synthesized here — no downloaded or licensed audio.
Music box tines (bell partials, soft attack, long decay), harp-like bass on beat 1, chords on 2–3, light reverb.
Stdlib only. Usage: python3 musica.py <out.wav> [seconds=26.5]"""
import math, struct, sys, wave, array, random

SR = 44100
out = sys.argv[1]
DUR = float(sys.argv[2]) if len(sys.argv) > 2 else 26.5
BEAT = 0.5                     # 120 bpm, a bar of 3/4 = 1.5 s
N = int(SR * (DUR + 2.5))
L = array.array('f', bytes(4 * N)); R = array.array('f', bytes(4 * N))

def hz(note):                  # 'F#5' → Hz
    names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
    n = names[note[0]] + (1 if '#' in note else 0); octv = int(note[-1])
    return 440.0 * 2 ** ((n + 12 * (octv + 1) - 69) / 12)

def tine(t0, note, vel=1.0, pan=0.0, decay=1.6, parts=((1, 1), (2.0, .28), (4.1, .10), (6.3, .04))):
    f = hz(note); i0 = int(t0 * SR); n = int(SR * min(decay * 3.2, 4.5))
    gl, gr = vel * (1 - pan) * .5, vel * (1 + pan) * .5
    for k in range(n):
        i = i0 + k
        if i >= N: break
        t = k / SR
        env = (1 - math.exp(-t * 900)) * math.exp(-t / decay)
        s = 0.0
        for m, a in parts: s += a * math.sin(2 * math.pi * f * m * t) * math.exp(-t * (m - 1) * 1.8)
        s *= env
        L[i] += s * gl; R[i] += s * gr

# melody: (bar, beat offset, note, length in beats unused by tines) — 16 bars + final chord
MEL = [
 (0,0,'F#5'),(0,1,'A5'),(0,2,'D6'),
 (1,0,'C#6'),(1,.5,'B5'),(1,1,'F#5'),
 (2,0,'G5'),(2,1,'B5'),(2,2,'D6'),
 (3,0,'C#6'),(3,.5,'E6'),(3,1,'A5'),
 (4,0,'F#6'),(4,1,'E6'),(4,1.5,'D6'),(4,2,'A5'),
 (5,0,'B5'),(5,1,'D6'),(5,2,'F#5'),
 (6,0,'G5'),(6,.5,'A5'),(6,1,'B5'),(6,2,'E6'),
 (7,0,'C#6'),(7,2,'A5'),
 (8,0,'A5'),(8,1,'D6'),(8,2,'F#6'),
 (9,0,'E6'),(9,.5,'C#6'),(9,1,'A5'),
 (10,0,'B5'),(10,1,'D6'),(10,2,'G6'),
 (11,0,'F#6'),(11,.5,'E6'),(11,1,'C#6'),
 (12,0,'D6'),(12,1,'F#6'),(12,2,'B5'),
 (13,0,'G5'),(13,1,'B5'),(13,2,'D6'),
 (14,0,'E6'),(14,.5,'D6'),(14,1,'C#6'),(14,2,'E6'),
 (15,0,'D6'),(15,1,'A5'),(15,2,'F#5'),
]
CH = ['D', 'Bm', 'G', 'A', 'D', 'Bm', 'Em', 'A', 'D', 'F#m', 'G', 'A', 'Bm', 'G', 'A', 'D']
TONES = {'D': ('D3', 'F#4', 'A4'), 'Bm': ('B2', 'D4', 'F#4'), 'G': ('G2', 'B3', 'D4'), 'A': ('A2', 'C#4', 'E4'),
         'Em': ('E3', 'G4', 'B4'), 'F#m': ('F#2', 'A3', 'C#4')}
BASS_PARTS = ((1, 1), (2.0, .35), (3.0, .08))
random.seed(7)
bars = int(DUR / (3 * BEAT)) + 1
for bar in range(min(bars, 17)):
    t = bar * 3 * BEAT
    if bar == 16:                                            # final ringing chord + high sparkle
        for i, nn in enumerate(('D3', 'A3', 'F#4', 'A4', 'D5', 'F#5', 'A5', 'D6')): tine(t + i * .06, nn, .55, (i % 3 - 1) * .4, 2.6)
        break
    b, c1, c2 = TONES[CH[bar]]
    tine(t, b, .55, -.2, 1.1, BASS_PARTS)
    for k in (1, 2): tine(t + k * BEAT, c1, .22, .25, .7); tine(t + k * BEAT, c2, .20, .35, .7)
for bar, off, note in MEL:
    if bar < bars: tine(bar * 3 * BEAT + off * BEAT + random.uniform(0, .008), note, .62, random.uniform(-.25, .25))
for t0 in (3.0, 21.6):                                       # shimmer on the title reveals
    for i, nn in enumerate(('A6', 'D7', 'F#6', 'A6', 'D7')): tine(t0 + i * .05, nn, .18, (i % 2) * .6 - .3, .9, ((1, 1), (2, .2)))

def reverb(x):                                              # small Schroeder: 4 combs + 2 allpass
    y = array.array('f', bytes(4 * len(x)))
    for d, g in ((1557, .80), (1617, .79), (1491, .78), (1422, .77)):
        buf = [0.0] * d; j = 0
        for i in range(len(x)):
            o = buf[j]; buf[j] = x[i] + o * g; j = (j + 1) % d; y[i] += o * .25
    for d, g in ((225, .5), (556, .5)):
        buf = [0.0] * d; j = 0
        for i in range(len(y)):
            b_ = buf[j]; v = y[i] + b_ * g; buf[j] = v; y[i] = b_ - v * g; j = (j + 1) % d
    return y
wl, wr = reverb(L), reverb(R)
peak = max(max(abs(L[i] + .35 * wl[i]), abs(R[i] + .35 * wr[i])) for i in range(N)) or 1
n_out = int(SR * DUR); fade = int(SR * 1.2)
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    fr = bytearray()
    for i in range(n_out):
        g = .8 / peak * min(1, (n_out - i) / fade) * min(1, i / 400)
        fr += struct.pack('<hh', int(32767 * (L[i] + .35 * wl[i]) * g), int(32767 * (R[i] + .35 * wr[i]) * g))
    w.writeframes(bytes(fr))
print('ok', out, DUR, 's')
