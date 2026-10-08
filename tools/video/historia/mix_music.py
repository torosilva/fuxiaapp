#!/usr/bin/env python3
"""Mix Carolina's voice (clips-carolina.tsv over a voice source) with a music bed for the 132 s story video.
Music: ducked under the voice (fast attack, slow release), louder in pauses, builds toward 05 · Fuxia 360 (78 s) and the
closing (124 s), fades out at the end. Output: a mono 44.1 kHz WAV aligned to the video timeline (mux it with a one-row
TSV "0 0 <dur>"). Needs numpy. Usage: python3 mix_music.py <voice.wav> <clips.tsv> <music.wav> <out.wav> [dur=132]"""
import sys, wave
import numpy as np

SR = 44100

def read(p):
    with wave.open(p) as w:
        assert w.getframerate() == SR, f'{p}: needs {SR} Hz (convert with afconvert -d LEI16@44100)'
        a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        return a.reshape(-1, w.getnchannels()).mean(axis=1)

voice_src, tsv, music_p, out = sys.argv[1:5]
dur = float(sys.argv[5]) if len(sys.argv) > 5 else 132.0
N = int(dur * SR)
src = read(voice_src)
voice = np.zeros(N, np.float32)
for line in open(tsv, encoding='utf8'):
    f = line.rstrip('\n').split('\t')
    if len(f) < 3 or not f[0].strip(): continue
    v, s, e = (float(x) for x in f[:3])
    a = src[int(s * SR):int(e * SR)]; i = int(v * SR); n = min(len(a), N - i)
    if n > 0: voice[i:i + n] += a[:n]

music = read(music_p)
if len(music) < N:                        # loop with a 2 s crossfade if the track is shorter than the video
    xf = 2 * SR; reps = [music]
    while sum(map(len, reps)) - xf * (len(reps) - 1) < N: reps.append(music)
    m = reps[0]
    for r in reps[1:]:
        ramp = np.linspace(0, 1, xf, dtype=np.float32)
        m = np.concatenate([m[:-xf], m[-xf:] * (1 - ramp) + r[:xf] * ramp, r[xf:]])
    music = m
music = music[:N]
music /= (np.percentile(np.abs(music), 99.5) + 1e-9)   # normalise the bed

# arc of the bed (linear gain): calm opening → workshop/stores → digital → builds into Fuxia 360 → peak at the closing
t = np.arange(N) / SR
arc = np.interp(t, [0, 5, 20, 32, 78, 97, 124, 129.5, dur - 2.2, dur], [.34, .30, .30, .32, .34, .40, .46, .52, .52, 0])
# ducking: envelope of the voice (10 ms attack, 350 ms release) → bed down to 20 % of its arc under speech
env = np.abs(voice); k = int(.01 * SR); env = np.convolve(env, np.ones(k) / k, 'same')
duck = np.zeros(N, np.float32); g = 0.0; rel = np.exp(-1 / (.35 * SR)); att = np.exp(-1 / (.01 * SR))
thr = .02
for i in range(0, N, 64):                  # block-wise for speed
    target = 1.0 if env[i] > thr else 0.0
    c = att if target > g else rel
    g = target + (g - target) * c ** 64
    duck[i:i + 64] = g
bed = music * arc * (1 - .8 * duck)
mix = voice * 1.0 + bed
peak = np.max(np.abs(mix));  mix = mix / peak * .92 if peak > .92 else mix
with wave.open(out, 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(mix, -1, 1) * 32767).astype(np.int16).tobytes())
print(f'ok {out} {dur:.1f}s · voice peak {np.max(np.abs(voice)):.2f} · bed peak {np.max(np.abs(bed)):.2f}')
