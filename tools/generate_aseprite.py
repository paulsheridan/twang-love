#!/usr/bin/env python3
"""
Generate .aseprite files for twang game animations.

Writes spec-compliant Aseprite files (see ase-file-specs.md):
  - 128-byte header (DWORD file size at 0, WORD magic 0xA5E0 at 4)
  - 16-byte frame headers (DWORD size, WORD 0xF1FA, ...)
  - Chunks with DWORD size + WORD type headers
  - Layer chunk 0x2004 (visible, opacity 255) in frame 0
  - Cel chunk 0x2005 type 2 (zlib-compressed RGBA) in every frame
  - Tags chunk 0x2018 in frame 0

Real sprite pixels are pulled from spritesheet.png (art cells are 16x16,
16 per row). Nothing is rendered or viewed; pixels are copied
programmatically.
"""

import os
import struct
import zlib

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "spritesheet.png")
OUT_DIR = os.path.join(ROOT, "animations", "generated")

CELL = 16
CELLS_PER_ROW = 16


def cell_pixels(sheet, index):
    """Return raw RGBA bytes (row-major) for art cell `index`."""
    col = index % CELLS_PER_ROW
    row = index // CELLS_PER_ROW
    box = (col * CELL, row * CELL, col * CELL + CELL, row * CELL + CELL)
    return sheet.crop(box).tobytes()


def ase_string(text):
    """Aseprite STRING: WORD byte length + UTF-8 bytes (no NUL)."""
    raw = text.encode("utf-8")
    return struct.pack("<H", len(raw)) + raw


def chunk(chunk_type, data):
    """Wrap chunk data with its DWORD size + WORD type header."""
    return struct.pack("<IH", len(data) + 6, chunk_type) + data


def layer_chunk(name="Layer 1"):
    """Layer chunk (0x2004): visible, editable, Normal blend, opacity 255."""
    data = b""
    data += struct.pack("<H", 3)   # flags: 1=visible, 2=editable
    data += struct.pack("<H", 0)   # type: normal image layer
    data += struct.pack("<H", 0)   # child level
    data += struct.pack("<H", 0)   # default width (ignored)
    data += struct.pack("<H", 0)   # default height (ignored)
    data += struct.pack("<H", 0)   # blend mode: Normal
    data += struct.pack("<B", 255) # opacity
    data += b"\x00" * 3            # future
    data += ase_string(name)
    return chunk(0x2004, data)


def cel_chunk(rgba, width, height, layer_index=0):
    """Cel chunk (0x2005) cel type 2: zlib-compressed RGBA image."""
    data = b""
    data += struct.pack("<H", layer_index)  # layer index
    data += struct.pack("<h", 0)            # x
    data += struct.pack("<h", 0)            # y
    data += struct.pack("<B", 255)          # opacity
    data += struct.pack("<H", 2)            # cel type: compressed image
    data += struct.pack("<h", 0)            # z-index
    data += b"\x00" * 5                     # future
    data += struct.pack("<H", width)        # width in pixels
    data += struct.pack("<H", height)       # height in pixels
    data += zlib.compress(bytes(rgba), 9)
    return chunk(0x2005, data)


def tags_chunk(tags):
    """Tags chunk (0x2018). tags: list of (name, from, to, direction)."""
    data = struct.pack("<H", len(tags))
    data += b"\x00" * 8  # future
    for name, frm, to, direction in tags:
        data += struct.pack("<H", frm)     # from frame
        data += struct.pack("<H", to)      # to frame
        data += struct.pack("<B", direction)  # 0=forward, 1=reverse, 2=ping-pong
        data += struct.pack("<H", 0)       # repeat 0 = default
        data += b"\x00" * 6                # future
        data += b"\x00" * 3                # rgb (deprecated)
        data += struct.pack("<B", 0)       # extra
        data += ase_string(name)
    return chunk(0x2018, data)


def frame(duration_ms, chunks):
    """Build one frame: 16-byte header + chunk bytes.

    The chunk count goes in the legacy WORD field with the extended DWORD
    left at 0. Aseprite's reader (aseprite_decoder.cpp readFrameHeader)
    only adopts the extended count when the legacy field is exactly 0xFFFF:

        if (chunks == 0xFFFF && chunks < nchunks) chunks = nchunks;

    Because that compares 0xFFFF against nchunks, writing 0xFFFF there
    leaves the count at 65535 for small frames and the reader walks off
    the end of the file. Writing the real count in the legacy field is
    always correct: the extended field is then simply ignored.
    """
    body = b"".join(chunks)
    header = struct.pack(
        "<IHHHHI",
        16 + len(body),   # DWORD bytes in this frame (incl. header)
        0xF1FA,           # WORD magic
        len(chunks),      # WORD legacy chunk count
        duration_ms,      # WORD duration ms
        0,                # BYTE[2] future
        0,                # DWORD extended chunk count (0 = use legacy)
    )
    return header + body


def aseprite_file(width, height, frames, tags):
    """Assemble the complete file. frames: list of (duration_ms, chunk_list)."""
    header = bytearray(128)
    struct.pack_into("<I", header, 0, 0)          # file size (patched below)
    struct.pack_into("<H", header, 4, 0xA5E0)     # magic
    struct.pack_into("<H", header, 6, len(frames))# frames
    struct.pack_into("<H", header, 8, width)      # width
    struct.pack_into("<H", header, 10, height)    # height
    struct.pack_into("<H", header, 12, 32)        # color depth: RGBA
    struct.pack_into("<I", header, 14, 1)         # flags: layer opacity valid
    struct.pack_into("<H", header, 18, 100)       # speed (deprecated)
    header[34] = 1                                # pixel width (aspect 1:1)
    header[35] = 1                                # pixel height
    struct.pack_into("<H", header, 40, width)     # grid width
    struct.pack_into("<H", header, 42, height)    # grid height

    # Chunks only exist inside frames; tags belong to frame 0.
    rendered = []
    for i, (dur, chunks) in enumerate(frames):
        if i == 0 and tags:
            chunks = list(chunks) + [tags_chunk(tags)]
        rendered.append(frame(dur, chunks))
    body = b"".join(rendered)
    struct.pack_into("<I", header, 0, 128 + len(body))
    return bytes(header) + body


def build_player(sheet):
    """idle, airborne, aim_down, landing, run(4) from art cells 96-103."""
    cells = list(range(96, 104))  # 96=idle, 97=airborne, 98=aim_down,
                                  # 99=landing, 100-103=run cycle
    duration = 200                # 6 world-steps @ 30hz (config.player.run_cycle)
    frames = []
    for i, idx in enumerate(cells):
        chunks = []
        if i == 0:
            chunks.append(layer_chunk("Player"))
        chunks.append(cel_chunk(cell_pixels(sheet, idx), CELL, CELL))
        frames.append((duration, chunks))
    tags = [
        ("idle", 0, 0, 0),
        ("airborne", 1, 1, 0),
        ("aim_down", 2, 2, 0),
        ("landing", 3, 3, 0),
        ("run", 4, 7, 0),
    ]
    return aseprite_file(CELL, CELL, frames, tags)


def build_enemies(sheet):
    """melee=105, archer=90, laser=138 (config.tiles)."""
    entries = [("melee", 105), ("archer", 90), ("laser", 138)]
    frames = []
    for i, (name, idx) in enumerate(entries):
        chunks = []
        if i == 0:
            chunks.append(layer_chunk("Enemies"))
        chunks.append(cel_chunk(cell_pixels(sheet, idx), CELL, CELL))
        frames.append((200, chunks))
    tags = [(name, i, i, 0) for i, (name, _) in enumerate(entries)]
    return aseprite_file(CELL, CELL, frames, tags)


def build_world(sheet):
    """Switch off/on (171/172) and spring collapsed/extended (16/32)."""
    entries = [
        ("switch_off", 171),
        ("switch_on", 172),
        ("spring_collapsed", 16),
        ("spring_extended", 32),
    ]
    frames = []
    for i, (name, idx) in enumerate(entries):
        chunks = []
        if i == 0:
            chunks.append(layer_chunk("World"))
        chunks.append(cel_chunk(cell_pixels(sheet, idx), CELL, CELL))
        frames.append((200, chunks))
    tags = [(name, i, i, 0) for i, (name, _) in enumerate(entries)]
    return aseprite_file(CELL, CELL, frames, tags)


def verify(path, expected_frames, expected_tags, sheet, cell_indices):
    """Parse the file back and check structure + pixel round-trip."""
    with open(path, "rb") as f:
        data = f.read()

    file_size = struct.unpack_from("<I", data, 0)[0]
    magic = struct.unpack_from("<H", data, 4)[0]
    nframes = struct.unpack_from("<H", data, 6)[0]
    width = struct.unpack_from("<H", data, 8)[0]
    height = struct.unpack_from("<H", data, 10)[0]
    bpp = struct.unpack_from("<H", data, 12)[0]
    assert magic == 0xA5E0, f"bad magic {magic:#x}"
    assert file_size == len(data), f"header size {file_size} != {len(data)}"
    assert nframes == expected_frames, f"frames {nframes} != {expected_frames}"
    assert (width, height, bpp) == (16, 16, 32), (width, height, bpp)

    pos = 128
    seen_tags = []
    layer_seen = 0
    for fi in range(nframes):
        fsize, fmagic, oldc, dur, _fut, newc = struct.unpack_from("<IHHHHI", data, pos)
        assert fmagic == 0xF1FA, f"frame {fi} bad magic"

        # Exact port of AsepriteDecoder::readFrameHeader: the extended
        # count is only adopted when the legacy field is 0xFFFF *and*
        # 0xFFFF < nchunks, which never holds for real chunk counts.
        nchunks = oldc
        if nchunks == 0xFFFF and nchunks < newc:
            nchunks = newc
        assert nchunks < 0xFFFF, (
            f"frame {fi} chunk count resolves to {nchunks}; Aseprite would "
            f"read past EOF"
        )

        cpos = pos + 16
        for _ in range(nchunks):
            csize, ctype = struct.unpack_from("<IH", data, cpos)
            assert csize >= 6, f"frame {fi} chunk size {csize} < 6"
            assert cpos + csize <= len(data), f"frame {fi} chunk past EOF"
            cdata = data[cpos + 6:cpos + csize]
            if ctype == 0x2004:
                layer_seen += 1
                flags, ltype = struct.unpack_from("<HH", cdata, 0)
                opacity = cdata[12]
                assert flags & 1, "layer not visible"
                assert opacity == 255, f"layer opacity {opacity}"
            elif ctype == 0x2005:
                layer_idx, x, y, cel_op, ctype2 = struct.unpack_from("<HhhBH", cdata, 0)
                cw, ch = struct.unpack_from("<HH", cdata, 16)
                raw = zlib.decompress(cdata[20:])
                assert (cw, ch) == (CELL, CELL), (cw, ch)
                assert len(raw) == CELL * CELL * 4, len(raw)
                expected = cell_pixels(sheet, cell_indices[fi])
                assert raw == expected, f"frame {fi} pixels differ from sheet cell"
            elif ctype == 0x2018:
                count = struct.unpack_from("<H", cdata, 0)[0]
                tpos = 10
                for _ in range(count):
                    frm, to, direction = struct.unpack_from("<HHB", cdata, tpos)
                    tpos += 7
                    tpos += 6 + 3 + 1  # future6 + rgb3 + extra1
                    nlen = struct.unpack_from("<H", cdata, tpos)[0]
                    name = cdata[tpos + 2:tpos + 2 + nlen].decode("utf-8")
                    tpos += 2 + nlen
                    seen_tags.append((name, frm, to, direction))
                assert tpos == len(cdata), "tag chunk not fully consumed"
            cpos += csize
        assert cpos - pos == fsize, f"frame {fi} size mismatch"
        pos += fsize
    assert pos == len(data), f"{len(data) - pos} trailing bytes"

    assert layer_seen == 1, f"expected exactly 1 layer chunk, got {layer_seen}"
    assert seen_tags == expected_tags, f"tags {seen_tags} != {expected_tags}"
    return True


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGBA")

    outputs = []

    path = os.path.join(OUT_DIR, "player_animations.aseprite")
    with open(path, "wb") as f:
        f.write(build_player(sheet))
    verify(path, 8,
           [("idle", 0, 0, 0), ("airborne", 1, 1, 0), ("aim_down", 2, 2, 0),
            ("landing", 3, 3, 0), ("run", 4, 7, 0)],
           sheet, list(range(96, 104)))
    outputs.append(path)

    path = os.path.join(OUT_DIR, "enemy_animations.aseprite")
    with open(path, "wb") as f:
        f.write(build_enemies(sheet))
    verify(path, 3,
           [("melee", 0, 0, 0), ("archer", 1, 1, 0), ("laser", 2, 2, 0)],
           sheet, [105, 90, 138])
    outputs.append(path)

    path = os.path.join(OUT_DIR, "world_animations.aseprite")
    with open(path, "wb") as f:
        f.write(build_world(sheet))
    verify(path, 4,
           [("switch_off", 0, 0, 0), ("switch_on", 1, 1, 0),
            ("spring_collapsed", 2, 2, 0), ("spring_extended", 3, 3, 0)],
           sheet, [171, 172, 16, 32])
    outputs.append(path)

    # The old effects file was built on the broken format and has no source
    # art (particles are procedural); drop it so only valid files remain.
    stale = os.path.join(OUT_DIR, "effect_animations.aseprite")
    if os.path.exists(stale):
        os.remove(stale)

    for p in outputs:
        print(f"OK {os.path.relpath(p, ROOT)} ({os.path.getsize(p)} bytes)")
    print("All files verified: header, frames, chunks, tags, pixel round-trip.")


if __name__ == "__main__":
    main()
