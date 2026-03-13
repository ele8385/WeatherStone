#!/usr/bin/env python3

import os
import shutil
from pathlib import Path


SOURCE_ROOT = Path("widget_assets/android_widget_png")
DRAWABLE_ROOT = Path("android/app/src/main/res/drawable-nodpi")
STATIC_STATES = [
    "calm",
    "rain",
    "snow",
    "fog",
    "heat",
    "typhoon",
    "severe_typhoon",
]
WINDY_STATE = "windy_sequence"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def png_files(path: Path) -> list[Path]:
    return sorted(
        file
        for file in path.iterdir()
        if file.is_file() and file.suffix.lower() == ".png"
    )


def copy_file(source: Path, target: Path) -> None:
    ensure_dir(target.parent)
    shutil.copy2(source, target)


def clear_matching(prefix: str) -> None:
    if not DRAWABLE_ROOT.exists():
        return
    for file in DRAWABLE_ROOT.iterdir():
        if file.is_file() and file.name.startswith(prefix) and file.suffix.lower() == ".png":
            file.unlink()


def export_static_state(state: str) -> list[str]:
    state_dir = SOURCE_ROOT / state
    ensure_dir(state_dir)
    files = png_files(state_dir)
    if not files:
        return []

    source = files[0]
    target_name = f"widget_stone_{state}.png"
    copy_file(source, DRAWABLE_ROOT / target_name)
    return [target_name]


def export_windy_sequence() -> list[str]:
    state_dir = SOURCE_ROOT / WINDY_STATE
    ensure_dir(state_dir)
    files = png_files(state_dir)
    clear_matching("widget_stone_windy_frame_")

    exported = []
    for index, source in enumerate(files):
        target_name = f"widget_stone_windy_frame_{index:02d}.png"
        copy_file(source, DRAWABLE_ROOT / target_name)
        exported.append(target_name)
    return exported


def main() -> None:
    ensure_dir(SOURCE_ROOT)
    ensure_dir(DRAWABLE_ROOT)

    lines = []
    windy_files = export_windy_sequence()
    lines.append(f"windy_sequence: {len(windy_files)} file(s) exported")

    for state in STATIC_STATES:
        exported = export_static_state(state)
        lines.append(f"{state}: {len(exported)} file(s) exported")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
