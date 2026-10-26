#!/usr/bin/env python3
"""Prepare the CC0 field recording as a soft, seamless study rain loop.

Run on macOS (afconvert), or pass an already decoded 16-bit WAV as argv[1].
Source and license: scripts/audio/README.md.
"""
from array import array
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temporary:
    decoded = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(temporary) / 'rain.wav'
    if len(sys.argv) == 1:
        subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16',
                        str(root / 'scripts/audio/study-rain-source.mp3'), str(decoded)], check=True)
    with wave.open(str(decoded), 'rb') as audio:
        rate, channels = audio.getframerate(), audio.getnchannels()
        assert audio.getsampwidth() == 2, 'Expected 16-bit PCM'
        samples = array('h', audio.readframes(audio.getnframes()))
    if sys.byteorder != 'little':
        samples.byteswap()

# Remove low rumble and soften bright hiss while retaining natural drops.
filtered = array('f', [0]) * len(samples)
low_alpha = 1 - math.exp(-2 * math.pi * 4200 / rate)
rumble_alpha = 1 - math.exp(-2 * math.pi * 90 / rate)
for channel in range(channels):
    low = rumble = 0.0
    # Warm the filters with the tail so the beginning has no startup transient.
    for i in range(len(samples) - rate * channels, len(samples), channels):
        value = samples[i + channel] / 32768
        rumble += rumble_alpha * (value - rumble)
        low += low_alpha * (value - rumble - low)
    for i in range(channel, len(samples), channels):
        value = samples[i] / 32768
        rumble += rumble_alpha * (value - rumble)
        low += low_alpha * (value - rumble - low)
        filtered[i] = low

# Equal-power overlap joins two seconds of tail and head without silence.
frames = len(samples) // channels
overlap = 2 * rate
loop = array('f')
for frame in range(overlap):
    t = frame / (overlap - 1)
    tail_gain, head_gain = math.cos(t * math.pi / 2), math.sin(t * math.pi / 2)
    for channel in range(channels):
        loop.append(filtered[(frames - overlap + frame) * channels + channel] * tail_gain
                    + filtered[frame * channels + channel] * head_gain)
loop.extend(filtered[overlap * channels:(frames - overlap) * channels])

# Consistent, quiet source level, with ample headroom for individual droplets.
rms = math.sqrt(sum(value * value for value in loop) / len(loop))
peak = max(abs(value) for value in loop)
gain = min(10 ** (-21 / 20) / rms, 0.85 / peak)
output = array('h', (round(value * gain * 32767) for value in loop))
if sys.byteorder != 'little':
    output.byteswap()
path = root / 'Sources/FocusCompanion/Resources/rain.wav'
with wave.open(str(path), 'wb') as audio:
    audio.setnchannels(channels)
    audio.setsampwidth(2)
    audio.setframerate(rate)
    audio.writeframes(output.tobytes())
print(f'{path}: {len(loop) / channels / rate:.1f}s, {channels} channels, {rate} Hz')
