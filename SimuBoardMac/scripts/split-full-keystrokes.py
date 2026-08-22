#!/usr/bin/env python3
"""Split audited full-keystroke recordings into press and release samples.

The split points were selected from the short-time energy envelope and spectral
flux of each recording.  They sit in the quiet valley immediately before the
release transient, rather than at an arbitrary fraction of the clip duration.
"""

from __future__ import annotations

import argparse
import math
import os
import sys
import wave
from array import array
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass(frozen=True)
class Split:
    press_end_ms: float
    release_end_ms: Optional[float] = None
    release_gain_db: float = 0.0
    release_source_row: Optional[int] = None
    release_start_ms: Optional[float] = None


# Release end points remove trailing room tone and, in continuous recordings,
# the beginning of the next keystroke. MX Clear R3 has no usable release
# transient, so it takes the closest clean variation from the same source pack.
SPLITS: dict[str, tuple[Split, ...]] = {
    "mxclear": (
        Split(78, 145),
        Split(175, 220),
        Split(168, 220, 6),
        Split(155, 220, release_source_row=4, release_start_ms=155),
        Split(155, 220),
    ),
    "studiotactile": (
        Split(124, 175),
        Split(118, 158),
        Split(125, 195),
        Split(109, 155),
        Split(140, 245, -5),
    ),
    "lowprofileblue": (
        Split(80, 150),
        Split(69, 125),
        Split(82, 130),
        Split(70, 105),
        Split(94, 128),
    ),
    "studioclicky": (
        Split(124, 215),
        Split(70, 185),
        Split(79, 160),
        Split(70, 145),
        Split(65, 150),
    ),
    "keychronred": (
        Split(75, 125),
        Split(85, 145),
        Split(87, 140),
        Split(65, 105, 6),
        Split(93, 145),
    ),
}

SAMPLE_RATE = 48_000
PRESS_FADE_OUT_MS = 4.0
RELEASE_FADE_IN_MS = 2.0
RELEASE_FADE_OUT_MS = 4.0


@dataclass
class WaveData:
    samples: array
    sample_rate: int


def read_wave(path: Path) -> WaveData:
    with wave.open(str(path), "rb") as source:
        if (
            source.getnchannels() != 1
            or source.getsampwidth() != 2
            or source.getframerate() != SAMPLE_RATE
            or source.getcomptype() != "NONE"
        ):
            raise ValueError(f"Expected 48 kHz mono 16-bit PCM WAV: {path}")
        samples = array("h")
        samples.frombytes(source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    return WaveData(samples=samples, sample_rate=SAMPLE_RATE)


def apply_linear_fade(samples: array, *, fade_in_ms: float, fade_out_ms: float) -> None:
    fade_in_frames = min(len(samples), round(SAMPLE_RATE * fade_in_ms / 1000))
    for index in range(fade_in_frames):
        samples[index] = round(samples[index] * index / max(1, fade_in_frames - 1))

    fade_out_frames = min(len(samples), round(SAMPLE_RATE * fade_out_ms / 1000))
    fade_start = len(samples) - fade_out_frames
    for index in range(fade_out_frames):
        samples[fade_start + index] = round(
            samples[fade_start + index]
            * (fade_out_frames - 1 - index)
            / max(1, fade_out_frames - 1)
        )


def apply_gain(samples: array, gain_db: float) -> None:
    if gain_db == 0:
        return
    multiplier = math.pow(10, gain_db / 20)
    for index, sample in enumerate(samples):
        samples[index] = max(-32768, min(32767, round(sample * multiplier)))


def write_wave(path: Path, samples: array) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output_samples = array("h", samples)
    if sys.byteorder != "little":
        output_samples.byteswap()
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with wave.open(str(temporary_path), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.setcomptype("NONE", "not compressed")
        target.writeframes(output_samples.tobytes())
    os.replace(temporary_path, path)


def frame_at(milliseconds: float, frame_count: int) -> int:
    return min(frame_count, max(0, round(milliseconds * SAMPLE_RATE / 1000)))


def split_profile(audio_root: Path, profile: str) -> None:
    profile_root = audio_root / profile
    source_path = profile_root / "full"
    expected_source_names = {f"GENERIC_R{row}.wav" for row in range(5)}
    actual_source_names = {entry.name for entry in source_path.iterdir()}
    if actual_source_names != expected_source_names:
        raise ValueError(
            f"Expected exactly five full recordings in {source_path}; "
            f"found {sorted(actual_source_names)}"
        )
    sources = tuple(
        read_wave(source_path / f"GENERIC_R{row}.wav")
        for row in range(5)
    )

    for row, split in enumerate(SPLITS[profile]):
        press_source = sources[row]
        press_end = frame_at(split.press_end_ms, len(press_source.samples))
        press = array("h", press_source.samples[:press_end])
        if len(press) < SAMPLE_RATE // 100:
            raise ValueError(f"Press segment is unexpectedly short: {profile} R{row}")
        apply_linear_fade(press, fade_in_ms=0, fade_out_ms=PRESS_FADE_OUT_MS)

        release_row = split.release_source_row if split.release_source_row is not None else row
        release_source = sources[release_row]
        release_start_ms = (
            split.release_start_ms
            if split.release_start_ms is not None
            else split.press_end_ms
        )
        release_start = frame_at(
            release_start_ms, len(release_source.samples)
        )
        release_end = (
            frame_at(split.release_end_ms, len(release_source.samples))
            if split.release_end_ms is not None
            else len(release_source.samples)
        )
        release = array("h", release_source.samples[release_start:release_end])
        if len(release) < SAMPLE_RATE // 100:
            raise ValueError(f"Release segment is unexpectedly short: {profile} R{row}")
        apply_linear_fade(
            release,
            fade_in_ms=RELEASE_FADE_IN_MS,
            fade_out_ms=RELEASE_FADE_OUT_MS,
        )
        apply_gain(release, split.release_gain_db)

        write_wave(profile_root / "press" / f"GENERIC_R{row}.wav", press)
        write_wave(profile_root / "release" / f"GENERIC_R{row}.wav", release)
        print(
            f"{profile} R{row}: press 0-{split.press_end_ms:g} ms; "
            f"release from R{release_row} "
            f"{release_start_ms:g}-{split.release_end_ms or 'end'} ms; "
            f"gain {split.release_gain_db:+g} dB"
        )

    for source_name in expected_source_names:
        (source_path / source_name).unlink()
    source_path.rmdir()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_root", type=Path)
    arguments = parser.parse_args()

    for profile in SPLITS:
        split_profile(arguments.audio_root, profile)


if __name__ == "__main__":
    main()
