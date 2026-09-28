#!/usr/bin/env python3
"""
Generate .aseprite files for twang game animations.
Creates properly formatted Aseprite files with animation tags.
"""

import struct
import os
import zlib


def create_aseprite_header(width, height, num_frames):
    """Create a 128-byte Aseprite file header."""
    header = bytearray(128)

    struct.pack_into('<I', header, 0, 0xA5E0)
    struct.pack_into('<H', header, 4, width)
    struct.pack_into('<H', header, 6, height)
    struct.pack_into('<H', header, 8, num_frames)
    struct.pack_into('<H', header, 10, 32)
    struct.pack_into('<I', header, 12, 1)
    struct.pack_into('<H', header, 16, 0)
    header[26] = 0
    struct.pack_into('<H', header, 30, 0)
    header[32] = 1
    header[33] = 1
    struct.pack_into('<h', header, 34, 0)
    struct.pack_into('<h', header, 36, 0)
    struct.pack_into('<H', header, 38, width)
    struct.pack_into('<H', header, 40, height)

    return header


def create_layer_chunk(name=b"Layer 1"):
    """Create a layer chunk (type 0x2004)."""
    data = bytearray(12)

    struct.pack_into('<H', data, 0, 1)
    struct.pack_into('<H', data, 2, 0)
    struct.pack_into('<H', data, 4, 0)
    struct.pack_into('<H', data, 6, 0)
    struct.pack_into('<H', data, 8, 0)
    struct.pack_into('<H', data, 10, 0)
    data.append(255)
    data.append(0)
    data.extend(name)
    data.append(0)

    chunk = bytearray(6)
    struct.pack_into('<I', chunk, 0, len(data) + 6)
    struct.pack_into('<H', chunk, 4, 0x2004)
    chunk.extend(data)

    return chunk


def create_cel_chunk(width, height, pixel_data):
    """Create a cel chunk (type 0x2005) with raw RGBA pixel data."""
    data = bytearray(9)

    struct.pack_into('<H', data, 0, 0)
    struct.pack_into('<h', data, 2, 0)
    struct.pack_into('<h', data, 4, 0)
    data.append(255)
    struct.pack_into('<H', data, 7, 0)
    data.extend(pixel_data)

    chunk = bytearray(6)
    struct.pack_into('<I', chunk, 0, len(data) + 6)
    struct.pack_into('<H', chunk, 4, 0x2005)
    chunk.extend(data)

    return chunk


def create_frame(pixel_data, width, height, duration_ms):
    """Create a single frame with layer and cel chunks."""
    frame = bytearray()

    frame_header = bytearray(6)
    struct.pack_into('<H', frame_header, 0, 0xF1FA)
    struct.pack_into('<H', frame_header, 2, 2)
    struct.pack_into('<H', frame_header, 4, duration_ms)

    frame.extend(frame_header)
    frame.extend(create_layer_chunk())
    frame.extend(create_cel_chunk(width, height, pixel_data))

    return frame


def create_tags_chunk(tags):
    """Create a tags chunk (type 0x2018).
    tags: list of (name, start_frame, end_frame, direction) tuples
    direction: 0=forward, 1=reverse, 2=ping-pong
    """
    data = bytearray()

    for name, start, end, direction in tags:
        tag_header = bytearray(10)
        struct.pack_into('<H', tag_header, 0, start)
        struct.pack_into('<H', tag_header, 2, end)
        tag_header[4] = direction
        data.extend(tag_header)
        data.extend(name.encode('utf-8'))
        data.append(0)

    chunk = bytearray(6)
    struct.pack_into('<I', chunk, 0, len(data) + 6)
    struct.pack_into('<H', chunk, 4, 0x2018)
    chunk.extend(data)

    return chunk


def create_aseprite_file(width, height, frames_data, frame_durations, tags=None):
    """Create a complete .aseprite file."""
    header = create_aseprite_header(width, height, len(frames_data))

    frames_bytes = bytearray()
    for pixel_data, duration in zip(frames_data, frame_durations):
        frames_bytes.extend(create_frame(pixel_data, width, height, duration))

    if tags:
        frames_bytes.extend(create_tags_chunk(tags))

    return bytes(header) + bytes(frames_bytes)


def create_placeholder_frame(width, height, color=(0, 0, 0, 0)):
    """Create a transparent frame."""
    return bytearray([color[0], color[1], color[2], color[3]] * (width * height))


def create_test_pattern_frame(width, height, frame_index):
    """Create a test pattern frame with a colored border."""
    pixels = bytearray(width * height * 4)

    colors = [
        (255, 0, 0, 255),
        (0, 255, 0, 255),
        (0, 0, 255, 255),
        (255, 255, 0, 255),
        (255, 0, 255, 255),
        (0, 255, 255, 255),
        (255, 255, 255, 255),
        (128, 128, 128, 255),
    ]

    color = colors[frame_index % len(colors)]

    for y in range(height):
        for x in range(width):
            idx = (y * width + x) * 4
            if x == 0 or x == width - 1 or y == 0 or y == height - 1:
                pixels[idx:idx+4] = bytes(color)
            elif (x + y + frame_index) % 4 == 0:
                pixels[idx:idx+4] = bytes((color[0] // 2, color[1] // 2, color[2] // 2, 255))

    return pixels


def generate_player_animations():
    """Generate the player animations .aseprite file."""
    width = 16
    height = 16

    # Frame layout:
    # 0: idle
    # 1: airborne
    # 2: aim_down
    # 3: landing
    # 4-7: run cycle (4 frames)

    num_frames = 8
    frame_duration = 200

    frames = []
    for i in range(num_frames):
        frames.append(create_test_pattern_frame(width, height, i))

    durations = [frame_duration] * num_frames

    tags = [
        ("idle", 0, 0, 0),
        ("airborne", 1, 1, 0),
        ("aim_down", 2, 2, 0),
        ("landing", 3, 3, 0),
        ("run", 4, 7, 0),
    ]

    return create_aseprite_file(width, height, frames, durations, tags)


def generate_enemy_animations():
    """Generate enemy animations .aseprite file."""
    width = 16
    height = 16

    # Frame layout for enemies:
    # 0: melee enemy idle
    # 1: melee enemy attack
    # 2: archer enemy idle
    # 3: archer enemy attack
    # 4: laser enemy idle
    # 5: laser enemy attack

    num_frames = 6
    frame_duration = 200

    frames = []
    for i in range(num_frames):
        frames.append(create_test_pattern_frame(width, height, i))

    durations = [frame_duration] * num_frames

    tags = [
        ("melee_idle", 0, 0, 0),
        ("melee_attack", 1, 1, 0),
        ("archer_idle", 2, 2, 0),
        ("archer_attack", 3, 3, 0),
        ("laser_idle", 4, 4, 0),
        ("laser_attack", 5, 5, 0),
    ]

    return create_aseprite_file(width, height, frames, durations, tags)


def generate_effect_animations():
    """Generate effect animations .aseprite file."""
    width = 16
    height = 16

    # Frame layout for effects:
    # 0-7: poof particles
    # 8-17: blood particles
    # 18-23: sparks
    # 24-29: smoke
    # 30-41: boom/explosion
    # 42-50: shards
    # 51-60: scorch
    # 61-74: spirit burst
    # 75-79: dust
    # 80-83: fire puff

    num_frames = 84
    frame_duration = 100

    frames = []
    for i in range(num_frames):
        frames.append(create_test_pattern_frame(width, height, i))

    durations = [frame_duration] * num_frames

    tags = [
        ("poof", 0, 7, 0),
        ("blood", 8, 17, 0),
        ("sparks", 18, 23, 0),
        ("smoke", 24, 29, 0),
        ("boom", 30, 41, 0),
        ("shards", 42, 50, 0),
        ("scorch", 51, 60, 0),
        ("spirit_burst", 61, 74, 0),
        ("dust", 75, 79, 0),
        ("fire_puff", 80, 83, 0),
    ]

    return create_aseprite_file(width, height, frames, durations, tags)


def main():
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'animations', 'generated')
    os.makedirs(output_dir, exist_ok=True)

    player_data = generate_player_animations()
    player_path = os.path.join(output_dir, 'player_animations.aseprite')
    with open(player_path, 'wb') as f:
        f.write(player_data)
    print(f"Created: {player_path} ({len(player_data)} bytes)")

    enemy_data = generate_enemy_animations()
    enemy_path = os.path.join(output_dir, 'enemy_animations.aseprite')
    with open(enemy_path, 'wb') as f:
        f.write(enemy_data)
    print(f"Created: {enemy_path} ({len(enemy_data)} bytes)")

    effect_data = generate_effect_animations()
    effect_path = os.path.join(output_dir, 'effect_animations.aseprite')
    with open(effect_path, 'wb') as f:
        f.write(effect_data)
    print(f"Created: {effect_path} ({len(effect_data)} bytes)")

    print("\nDone! Open these files in Aseprite to edit the animations.")
    print("The frames use test patterns so you can see the animation structure.")
    print("Replace the pixel data with your actual sprite art.")


if __name__ == '__main__':
    main()
