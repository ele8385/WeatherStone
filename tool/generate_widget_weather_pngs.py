#!/usr/bin/env python3

import math
import os
import sys
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

from generate_widget_png_sequence import (  # noqa: E402
    HEIGHT,
    WIDTH,
    add_highlights,
    draw_disc,
    draw_polyline,
    fill_polygon,
    irregular_stone_points,
    quadratic_points,
    write_png,
)


SOURCE_ROOT = Path("widget_assets/android_widget_png")
STATE_FILES = {
    "calm": "base.png",
    "rain": "base.png",
    "snow": "base.png",
    "fog": "base.png",
    "heat": "base.png",
    "typhoon": "base.png",
    "severe_typhoon": "base.png",
}


def blend_pixel(buffer, x, y, color):
    if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
        return

    src_r, src_g, src_b, src_a = color
    if src_a <= 0:
        return

    index = (y * WIDTH + x) * 4
    dst_r = buffer[index]
    dst_g = buffer[index + 1]
    dst_b = buffer[index + 2]
    dst_a = buffer[index + 3]

    src_alpha = src_a / 255.0
    dst_alpha = dst_a / 255.0
    out_alpha = src_alpha + dst_alpha * (1.0 - src_alpha)
    if out_alpha <= 0:
        return

    out_r = int(
        round(((src_r * src_alpha) + (dst_r * dst_alpha * (1.0 - src_alpha))) / out_alpha)
    )
    out_g = int(
        round(((src_g * src_alpha) + (dst_g * dst_alpha * (1.0 - src_alpha))) / out_alpha)
    )
    out_b = int(
        round(((src_b * src_alpha) + (dst_b * dst_alpha * (1.0 - src_alpha))) / out_alpha)
    )
    out_a = int(round(out_alpha * 255.0))

    buffer[index] = max(0, min(255, out_r))
    buffer[index + 1] = max(0, min(255, out_g))
    buffer[index + 2] = max(0, min(255, out_b))
    buffer[index + 3] = max(0, min(255, out_a))


def draw_line(buffer, start, end, radius, color):
    x0, y0 = start
    x1, y1 = end
    distance = math.hypot(x1 - x0, y1 - y0)
    steps = max(2, int(math.ceil(distance / max(radius * 0.6, 1.0))))
    for step in range(steps + 1):
        t = step / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        draw_disc(buffer, x, y, radius, color)


def render_base_stone(
    *,
    swing=0.0,
    bob=0.0,
    rope_flex=0.0,
    stone_tilt=0.0,
    wet=False,
    hot=False,
    fog=False,
    snow=False,
    missing=False,
    severe=False,
):
    frame = bytearray(WIDTH * HEIGHT * 4)
    anchor = (WIDTH / 2.0, 22.0)
    rope_length = 128.0
    stone_center = (
        anchor[0] + math.sin(swing) * rope_length,
        anchor[1] + math.cos(swing) * rope_length + 142.0 + bob,
    )
    knot = (
        stone_center[0] - math.sin(stone_tilt) * 10.0,
        stone_center[1] - math.cos(stone_tilt) * 62.0,
    )
    control = (
        anchor[0] + math.sin(swing * 0.65) * 28.0 + rope_flex,
        anchor[1] + 92.0,
    )
    rope_points = quadratic_points(anchor, control, knot, 28)

    draw_polyline(frame, rope_points, 7.0, (39, 26, 19, 54))
    draw_polyline(frame, rope_points, 4.3, (201, 182, 160, 214))
    draw_polyline(frame, rope_points, 2.1, (245, 232, 220, 134))
    draw_disc(frame, anchor[0], anchor[1], 6.0, (36, 29, 24, 160))

    if not missing:
        draw_disc(frame, knot[0], knot[1], 6.0, (45, 38, 32, 150))
        stone_points = irregular_stone_points(stone_center, 82.0, 62.0, stone_tilt)
        fill_polygon(frame, stone_points, stone_center, stone_tilt, 82.0, 62.0)
        add_highlights(frame, stone_center, stone_tilt, 82.0, 62.0)

        if wet:
            for offset in range(10):
                angle = stone_tilt - 0.4 + offset * 0.07
                hx = stone_center[0] + math.cos(angle) * 48
                hy = stone_center[1] + math.sin(angle) * 24 - 8
                draw_disc(frame, hx, hy, 10 - offset * 0.5, (178, 212, 224, max(12, 38 - offset * 2)))
            for drop_x, drop_y in [(-36, 24), (6, 38), (42, 18)]:
                draw_line(
                    frame,
                    (stone_center[0] + drop_x, stone_center[1] + drop_y),
                    (stone_center[0] + drop_x - 5, stone_center[1] + drop_y + 26),
                    2.0,
                    (128, 184, 210, 110),
                )

        if hot:
            for y in range(HEIGHT):
                for x in range(WIDTH):
                    index = (y * WIDTH + x) * 4 + 3
                    if frame[index] > 0:
                        blend_pixel(frame, x, y, (162, 62, 36, 42))
            for column in range(3):
                base_x = stone_center[0] - 26 + column * 26
                wave = []
                for step in range(8):
                    py = stone_center[1] - 88 - step * 18
                    px = base_x + math.sin(step * 0.8 + column) * 6
                    wave.append((px, py))
                draw_polyline(frame, wave, 2.2, (255, 166, 92, 62))

        if snow:
            for offset in range(28):
                theta = math.pi + (offset / 27.0) * math.pi
                px = stone_center[0] + math.cos(theta) * 66
                py = stone_center[1] - 20 + math.sin(theta) * 22
                draw_disc(frame, px, py, 10, (247, 250, 255, 185))
            for flake_x, flake_y in [(-48, -8), (-18, -24), (18, -28), (46, -12)]:
                draw_disc(frame, stone_center[0] + flake_x, stone_center[1] + flake_y, 4.2, (255, 255, 255, 190))

        if fog:
            mist_centers = [
                (-58, -10, 34, 24),
                (-14, -24, 38, 26),
                (34, -8, 32, 22),
                (-36, 26, 30, 20),
                (18, 30, 34, 24),
            ]
            for offset_x, offset_y, radius, base_alpha in mist_centers:
                for layer in range(6):
                    draw_disc(
                        frame,
                        stone_center[0] + offset_x + layer * 2,
                        stone_center[1] + offset_y + math.sin(layer * 0.8) * 3,
                        radius - layer * 3,
                        (238, 241, 245, max(6, base_alpha - layer * 4)),
                    )

    if severe:
        cracks = [
            ((60, 20), (138, 94), (172, 164)),
            ((298, 18), (242, 96), (208, 172)),
            ((192, 60), (196, 154), (188, 246)),
            ((102, 244), (166, 214), (214, 206)),
        ]
        for a, b, c in cracks:
            draw_line(frame, a, b, 1.6, (245, 246, 252, 150))
            draw_line(frame, b, c, 1.2, (245, 246, 252, 138))

    return frame


def generate_all_states():
    states = {
        "calm": render_base_stone(),
        "rain": render_base_stone(wet=True),
        "snow": render_base_stone(snow=True),
        "fog": render_base_stone(fog=True),
        "heat": render_base_stone(hot=True),
        "typhoon": render_base_stone(swing=0.15, rope_flex=12.0, missing=True),
        "severe_typhoon": render_base_stone(swing=0.22, rope_flex=18.0, missing=True, severe=True),
    }

    for state, frame in states.items():
        directory = SOURCE_ROOT / state
        directory.mkdir(parents=True, exist_ok=True)
        write_png(str(directory / STATE_FILES[state]), WIDTH, HEIGHT, frame)


if __name__ == "__main__":
    generate_all_states()
