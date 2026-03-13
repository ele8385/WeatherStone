#!/usr/bin/env python3

from pathlib import Path
import math
import sys


TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

from generate_widget_weather_pngs import render_base_stone  # noqa: E402
from generate_widget_png_sequence import write_png, WIDTH, HEIGHT  # noqa: E402


DRAWABLE_DIR = Path("android/app/src/main/res/drawable")
DRAWABLE_NODPI_DIR = Path("android/app/src/main/res/drawable-nodpi")


STATE_CONFIGS = {
    "calm": {
        "frames": 14,
        "duration": 160,
        "swing": 0.012,
        "bob": 1.0,
        "flex": 4.0,
        "swing_harmonic": 0.22,
        "bob_harmonic": 0.16,
        "tilt_factor": 1.02,
        "phase_offset": 0.55,
    },
    "windy": {"frames": 24, "duration": 50, "swing": 0.29, "bob": 5.0, "flex": 22.0},
    "rain": {
        "frames": 14,
        "duration": 132,
        "swing": 0.026,
        "bob": 2.4,
        "flex": 7.4,
        "swing_harmonic": 0.30,
        "bob_harmonic": 0.24,
        "tilt_factor": 1.05,
        "phase_offset": 0.25,
        "wet": True,
    },
    "snow": {
        "frames": 14,
        "duration": 176,
        "swing": 0.015,
        "bob": 1.2,
        "flex": 4.8,
        "swing_harmonic": 0.18,
        "bob_harmonic": 0.14,
        "tilt_factor": 1.0,
        "phase_offset": 1.05,
        "snow": True,
    },
    "fog": {
        "frames": 14,
        "duration": 188,
        "swing": 0.011,
        "bob": 0.85,
        "flex": 3.8,
        "swing_harmonic": 0.16,
        "bob_harmonic": 0.12,
        "tilt_factor": 1.0,
        "phase_offset": 1.45,
        "fog": True,
    },
    "heat": {
        "frames": 14,
        "duration": 145,
        "swing": 0.020,
        "bob": 1.8,
        "flex": 5.7,
        "swing_harmonic": 0.24,
        "bob_harmonic": 0.20,
        "tilt_factor": 1.04,
        "phase_offset": 0.85,
        "hot": True,
    },
    "typhoon": {
        "frames": 12,
        "duration": 96,
        "swing": 0.060,
        "bob": 2.0,
        "flex": 15.0,
        "swing_harmonic": 0.45,
        "bob_harmonic": 0.28,
        "tilt_factor": 1.12,
        "phase_offset": 0.10,
        "missing": True,
    },
    "severe_typhoon": {
        "frames": 12,
        "duration": 78,
        "swing": 0.085,
        "bob": 2.5,
        "flex": 19.0,
        "swing_harmonic": 0.52,
        "bob_harmonic": 0.34,
        "tilt_factor": 1.18,
        "phase_offset": 0.35,
        "missing": True,
        "severe": True,
    },
}


def render_state_frame(state: str, index: int, frames: int, config: dict) -> bytearray:
    if state == "windy":
        t = (math.tau * index) / frames
        swing = 0.29 * math.sin(t)
        swing += 0.06 * math.sin(2.0 * t - 0.7)
        swing += 0.02 * math.sin(3.0 * t + 1.1)
        bob = 5.0 * math.sin(t - 0.35) + 1.6 * math.sin(2.0 * t + 0.2)
        rope_flex = 22.0 * math.sin(t + math.pi / 2.0)
        stone_tilt = swing * 1.18 + 0.05 * math.sin(t - 0.45)
    else:
        t = (math.tau * index) / frames
        phase_offset = config.get("phase_offset", 0.0)
        swing_harmonic = config.get("swing_harmonic", 0.35)
        bob_harmonic = config.get("bob_harmonic", 0.3)
        tilt_factor = config.get("tilt_factor", 1.08)
        swing = config["swing"] * math.sin(t + phase_offset)
        swing += config["swing"] * swing_harmonic * math.sin(2.0 * t - 0.6 + phase_offset)
        bob = config["bob"] * math.sin(t - 0.25 + phase_offset * 0.5)
        bob += config["bob"] * bob_harmonic * math.sin(2.0 * t + 0.1 + phase_offset)
        rope_flex = config["flex"] * math.sin(t + math.pi / 2.0 + phase_offset)
        stone_tilt = swing * tilt_factor + 0.014 * math.sin(t - 0.45 + phase_offset)

    return render_base_stone(
        swing=swing,
        bob=bob,
        rope_flex=rope_flex,
        stone_tilt=stone_tilt,
        wet=config.get("wet", False),
        hot=config.get("hot", False),
        fog=config.get("fog", False),
        snow=config.get("snow", False),
        missing=config.get("missing", False),
        severe=config.get("severe", False),
    )


def write_animation_xml(state: str, frames: int, duration: int) -> None:
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<animation-list xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:oneshot="false">',
    ]
    for index in range(frames):
        lines.append(
            f'    <item android:drawable="@drawable/widget_stone_{state}_frame_{index:02d}" '
            f'android:duration="{duration}" />'
        )
    lines.append("</animation-list>")
    (DRAWABLE_DIR / f"widget_stone_animation_{state}.xml").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )


def generate_state_assets(state: str, config: dict) -> None:
    frames = config["frames"]
    for index in range(frames):
        frame = render_state_frame(state, index, frames, config)
        write_png(
            str(DRAWABLE_NODPI_DIR / f"widget_stone_{state}_frame_{index:02d}.png"),
            WIDTH,
            HEIGHT,
            frame,
        )
    write_animation_xml(state, frames, config["duration"])


def main() -> None:
    DRAWABLE_DIR.mkdir(parents=True, exist_ok=True)
    DRAWABLE_NODPI_DIR.mkdir(parents=True, exist_ok=True)
    for state, config in STATE_CONFIGS.items():
        generate_state_assets(state, config)


if __name__ == "__main__":
    main()
