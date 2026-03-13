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
    "calm": {"frames": 12, "duration": 140, "swing": 0.018, "bob": 1.8, "flex": 6.0},
    "windy": {"frames": 24, "duration": 55, "swing": 0.29, "bob": 5.0, "flex": 22.0},
    "rain": {"frames": 12, "duration": 135, "swing": 0.022, "bob": 2.0, "flex": 6.5, "wet": True},
    "snow": {"frames": 12, "duration": 145, "swing": 0.02, "bob": 1.6, "flex": 5.5, "snow": True},
    "fog": {"frames": 12, "duration": 150, "swing": 0.017, "bob": 1.4, "flex": 5.0, "fog": True},
    "heat": {"frames": 12, "duration": 138, "swing": 0.021, "bob": 2.1, "flex": 6.0, "hot": True},
    "typhoon": {"frames": 12, "duration": 120, "swing": 0.035, "bob": 1.2, "flex": 11.0, "missing": True},
    "severe_typhoon": {
        "frames": 12,
        "duration": 115,
        "swing": 0.045,
        "bob": 1.0,
        "flex": 13.0,
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
        swing = config["swing"] * math.sin(t)
        swing += config["swing"] * 0.35 * math.sin(2.0 * t - 0.6)
        bob = config["bob"] * math.sin(t - 0.25)
        bob += config["bob"] * 0.3 * math.sin(2.0 * t + 0.1)
        rope_flex = config["flex"] * math.sin(t + math.pi / 2.0)
        stone_tilt = swing * 1.08 + 0.014 * math.sin(t - 0.45)

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
