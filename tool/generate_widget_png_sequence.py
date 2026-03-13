#!/usr/bin/env python3

import math
import os
import struct
import zlib


FRAME_COUNT = 24
FRAME_DURATION_MS = 55
WIDTH = 384
HEIGHT = 384
OUTPUT_DIR = "android/app/src/main/res/drawable-nodpi"
OUTPUT_PREFIX = "widget_stone_windy_frame_"
SOURCE_SEQUENCE_DIR = "widget_assets/android_widget_png/windy_sequence"


def clamp(value, low, high):
    return max(low, min(high, value))


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

    out_r = (
        (src_r * src_alpha) + (dst_r * dst_alpha * (1.0 - src_alpha))
    ) / out_alpha
    out_g = (
        (src_g * src_alpha) + (dst_g * dst_alpha * (1.0 - src_alpha))
    ) / out_alpha
    out_b = (
        (src_b * src_alpha) + (dst_b * dst_alpha * (1.0 - src_alpha))
    ) / out_alpha

    buffer[index] = int(clamp(round(out_r), 0, 255))
    buffer[index + 1] = int(clamp(round(out_g), 0, 255))
    buffer[index + 2] = int(clamp(round(out_b), 0, 255))
    buffer[index + 3] = int(clamp(round(out_alpha * 255.0), 0, 255))


def draw_disc(buffer, cx, cy, radius, color):
    left = max(0, int(math.floor(cx - radius)))
    right = min(WIDTH - 1, int(math.ceil(cx + radius)))
    top = max(0, int(math.floor(cy - radius)))
    bottom = min(HEIGHT - 1, int(math.ceil(cy + radius)))
    radius_sq = radius * radius

    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            if dx * dx + dy * dy <= radius_sq:
                blend_pixel(buffer, x, y, color)


def draw_polyline(buffer, points, radius, color):
    for start, end in zip(points, points[1:]):
        x0, y0 = start
        x1, y1 = end
        distance = math.hypot(x1 - x0, y1 - y0)
        steps = max(2, int(math.ceil(distance / max(radius * 0.7, 1.0))))
        for step in range(steps + 1):
            t = step / steps
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            draw_disc(buffer, x, y, radius, color)


def quadratic_points(start, control, end, steps):
    points = []
    for index in range(steps + 1):
        t = index / steps
        mt = 1.0 - t
        x = (mt * mt * start[0]) + (2 * mt * t * control[0]) + (t * t * end[0])
        y = (mt * mt * start[1]) + (2 * mt * t * control[1]) + (t * t * end[1])
        points.append((x, y))
    return points


def point_in_polygon(px, py, polygon):
    inside = False
    previous_x, previous_y = polygon[-1]
    for current_x, current_y in polygon:
        crosses = ((current_y > py) != (previous_y > py))
        if crosses:
            intersection = (previous_x - current_x) * (py - current_y) / (
                previous_y - current_y
            ) + current_x
            if px < intersection:
                inside = not inside
        previous_x, previous_y = current_x, current_y
    return inside


def fill_polygon(buffer, polygon, center, rotation, rx, ry):
    min_x = max(0, int(math.floor(min(point[0] for point in polygon))))
    max_x = min(WIDTH - 1, int(math.ceil(max(point[0] for point in polygon))))
    min_y = max(0, int(math.floor(min(point[1] for point in polygon))))
    max_y = min(HEIGHT - 1, int(math.ceil(max(point[1] for point in polygon))))

    cx, cy = center
    cos_r = math.cos(-rotation)
    sin_r = math.sin(-rotation)

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            sample_x = x + 0.5
            sample_y = y + 0.5
            if not point_in_polygon(sample_x, sample_y, polygon):
                continue

            local_x = ((sample_x - cx) * cos_r) - ((sample_y - cy) * sin_r)
            local_y = ((sample_x - cx) * sin_r) + ((sample_y - cy) * cos_r)

            norm = math.sqrt((local_x / rx) ** 2 + (local_y / ry) ** 2)
            edge_softness = clamp((1.05 - norm) / 0.35, 0.0, 1.0)
            if edge_softness <= 0:
                continue

            light = 0.74 + (-local_x / rx) * 0.11 + (-local_y / ry) * 0.09
            noise = (
                math.sin(local_x * 0.19 + local_y * 0.11)
                + math.sin(local_x * 0.07 - local_y * 0.15)
            ) * 0.035
            warmth = 0.02 * math.sin(local_y * 0.1)
            shade = clamp(light + noise + warmth, 0.5, 1.0)

            base_r = int(clamp(122 * shade + 16, 0, 255))
            base_g = int(clamp(116 * shade + 12, 0, 255))
            base_b = int(clamp(110 * shade + 9, 0, 255))
            alpha = int(clamp(230 * edge_softness + 20, 0, 255))

            blend_pixel(buffer, x, y, (base_r, base_g, base_b, alpha))

            speckle = math.sin(local_x * 0.42 - local_y * 0.28) + math.sin(
                local_x * 0.16 + local_y * 0.31
            )
            if speckle > 1.45:
                blend_pixel(buffer, x, y, (72, 66, 64, int(alpha * 0.26)))


def irregular_stone_points(center, rx, ry, rotation):
    cx, cy = center
    points = []
    for index in range(18):
        theta = (math.tau * index) / 18.0
        warp = 1.0
        warp += 0.08 * math.sin(theta * 3.0 + 0.6)
        warp += 0.05 * math.sin(theta * 5.0 - 1.1)
        local_x = math.cos(theta) * rx * warp
        local_y = math.sin(theta) * ry * (0.94 + 0.04 * math.sin(theta * 2.0 + 0.2))
        x = cx + local_x * math.cos(rotation) - local_y * math.sin(rotation)
        y = cy + local_x * math.sin(rotation) + local_y * math.cos(rotation)
        points.append((x, y))
    return points


def add_highlights(buffer, center, rotation, rx, ry):
    cx, cy = center
    for offset in range(12):
        angle = rotation - 0.55 + offset * 0.06
        hx = cx + math.cos(angle) * rx * 0.44
        hy = cy + math.sin(angle) * ry * 0.42 - 10
        radius = 14 - offset * 0.75
        alpha = int(max(0, 20 - offset))
        draw_disc(buffer, hx, hy, radius, (255, 247, 240, alpha))


def write_png(path, width, height, buffer):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rows = []
    for y in range(height):
        start = y * width * 4
        end = start + width * 4
        rows.append(b"\x00" + bytes(buffer[start:end]))
    raw = b"".join(rows)

    def chunk(tag, data):
        return (
            struct.pack("!I", len(data))
            + tag
            + data
            + struct.pack("!I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(raw, 9)

    with open(path, "wb") as file:
        file.write(b"\x89PNG\r\n\x1a\n")
        file.write(chunk(b"IHDR", ihdr))
        file.write(chunk(b"IDAT", compressed))
        file.write(chunk(b"IEND", b""))


def render_frame(index):
    frame = bytearray(WIDTH * HEIGHT * 4)
    t = (math.tau * index) / FRAME_COUNT

    swing = 0.29 * math.sin(t)
    swing += 0.06 * math.sin(2.0 * t - 0.7)
    swing += 0.02 * math.sin(3.0 * t + 1.1)
    bob = 5.0 * math.sin(t - 0.35) + 1.6 * math.sin(2.0 * t + 0.2)
    rope_flex = 22.0 * math.sin(t + math.pi / 2.0)
    stone_tilt = swing * 1.18 + 0.05 * math.sin(t - 0.45)

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
        anchor[1] + 92.0 + 8.0 * math.cos(t + 0.35),
    )

    rope_points = quadratic_points(anchor, control, knot, 28)
    draw_polyline(frame, rope_points, 7.0, (39, 26, 19, 54))
    draw_polyline(frame, rope_points, 4.3, (201, 182, 160, 214))
    draw_polyline(frame, rope_points, 2.1, (245, 232, 220, 134))

    draw_disc(frame, anchor[0], anchor[1], 6.0, (36, 29, 24, 160))
    draw_disc(frame, knot[0], knot[1], 6.0, (45, 38, 32, 150))

    stone_points = irregular_stone_points(stone_center, 82.0, 62.0, stone_tilt)
    fill_polygon(frame, stone_points, stone_center, stone_tilt, 82.0, 62.0)
    add_highlights(frame, stone_center, stone_tilt, 82.0, 62.0)

    return frame


def build_animation_xml():
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<animation-list xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:oneshot="false">',
    ]
    for index in range(FRAME_COUNT):
        lines.append(
            f'    <item android:drawable="@drawable/{OUTPUT_PREFIX}{index:02d}" '
            f'android:duration="{FRAME_DURATION_MS}" />'
        )
    lines.append("</animation-list>")
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(SOURCE_SEQUENCE_DIR, exist_ok=True)
    for index in range(FRAME_COUNT):
        frame = render_frame(index)
        export_name = f"{OUTPUT_PREFIX}{index:02d}.png"
        source_name = f"frame_{index:02d}.png"
        write_png(os.path.join(OUTPUT_DIR, export_name), WIDTH, HEIGHT, frame)
        write_png(os.path.join(SOURCE_SEQUENCE_DIR, source_name), WIDTH, HEIGHT, frame)

    animation_path = "android/app/src/main/res/drawable/widget_stone_animation.xml"
    with open(animation_path, "w", encoding="utf-8") as file:
        file.write(build_animation_xml())


if __name__ == "__main__":
    main()
