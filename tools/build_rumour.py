#!/usr/bin/env python3
"""Derive the :rumour (2-bit) player art from the :myth (8-bit) art.

    python3 tools/build_rumour.py sprites/player

The low tier is NOT drawn by hand -- it is generated from the 8-bit sprites,
so the two tiers cannot drift apart. Re-run this after changing any myth
player art; the rumour art is a build product and is regenerated, not edited.

Two reductions, both of which have to happen for the step-up to read as
fidelity arriving rather than as a palette swap:

  COLOUR   four tones, the classic Game Boy DMG ramp.
  DETAIL   2x2 blocks vote on a single tone, so the figure is built from a
           quarter as many pixels of real information.

Written with only the standard library (no Pillow), because this repo has no
Python dependencies and adding one for a build step nobody runs daily is a
bad trade.
"""

import os
import struct
import sys
import zlib

# The classic DMG four-tone ramp, darkest first.
DMG = [(0x0f, 0x38, 0x0f), (0x30, 0x62, 0x30),
       (0x8b, 0xac, 0x0f), (0x9b, 0xbc, 0x0f)]

# Luminance cuts, taken from the 8-bit art's OWN distribution rather than at
# even steps. 38% of its pixels are pure black outline and the rest bunch
# between 40 and 100, so even bands drop 88% of the figure into two tones and
# it reads as a blob. These cuts clear the coat (which spans 57-83) in one
# piece and spend the two light greens on leather and skin.
EDGES = [12, 88, 140]

BLOCK = 2


def luminance(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def tone(r, g, b):
    index = 0
    for edge in EDGES:
        if luminance(r, g, b) >= edge:
            index += 1
    return DMG[index]


def read_png(path):
    """Minimal PNG reader: 8-bit, non-interlaced, any colour type."""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{path} is not a PNG'

    pos, idat, plte, trns, ihdr = 8, b'', None, None, None
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        pos += 8
        chunk = data[pos:pos + length]
        pos += length + 4
        if kind == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', chunk)
        elif kind == b'PLTE':
            plte = chunk
        elif kind == b'tRNS':
            trns = chunk
        elif kind == b'IDAT':
            idat += chunk
        elif kind == b'IEND':
            break

    width, height, depth, colour, _, _, interlace = ihdr
    assert depth == 8 and interlace == 0, f'{path}: only 8-bit non-interlaced'
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]

    raw = zlib.decompress(idat)
    stride = width * channels
    out, prev, pos = bytearray(), bytearray(stride), 0
    for _ in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 255
            elif filt == 2:
                line[i] = (line[i] + b) & 255
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        out += line
        prev = line

    pixels = []
    for y in range(height):
        row = []
        for x in range(width):
            i = y * stride + x * channels
            if colour == 6:
                row.append(tuple(out[i:i + 4]))
            elif colour == 2:
                row.append((out[i], out[i + 1], out[i + 2], 255))
            elif colour == 3:
                idx = out[i]
                r, g, b = plte[idx * 3:idx * 3 + 3]
                a = trns[idx] if trns and idx < len(trns) else 255
                row.append((r, g, b, a))
            elif colour == 4:
                row.append((out[i], out[i], out[i], out[i + 1]))
            else:
                row.append((out[i], out[i], out[i], 255))
        pixels.append(row)
    return width, height, pixels


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw += bytes(pixels[y][x])

    def chunk(kind, payload):
        head = struct.pack('>I', len(payload)) + kind + payload
        return head + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(png)


def reduce_sprite(pixels, width, height):
    """Four tones and a quarter of the pixels, feet kept on the ground.

    The block grid is anchored to the FIGURE'S LOWEST ROW, not to the canvas.
    A canvas-aligned grid puts the bottom of the figure at a different place
    within a block from frame to frame, so his feet snap up and down by a
    pixel as he walks -- about 3.5 screen px of bob the 8-bit art does not
    have. Anchoring to the feet reproduces the source's registration exactly.
    """
    rows = [y for y in range(height)
            if any(pixels[y][x][3] >= 8 for x in range(width))]
    offset = (rows[-1] + 1) % BLOCK if rows else 0

    out = [[(0, 0, 0, 0)] * width for _ in range(height)]
    for top in range(-offset, height, BLOCK):
        for left in range(0, width, BLOCK):
            votes, opaque, total = {}, 0, 0
            for y in range(max(top, 0), min(top + BLOCK, height)):
                for x in range(left, min(left + BLOCK, width)):
                    total += 1
                    r, g, b, a = pixels[y][x]
                    if a < 8:
                        continue
                    opaque += 1
                    key = tone(r, g, b)
                    votes[key] = votes.get(key, 0) + 1

            # A block less than half covered stays transparent, which is what
            # keeps the silhouette from bloating outward by a pixel.
            if opaque * 2 < total:
                continue

            colour = max(votes.items(), key=lambda kv: kv[1])[0]
            for y in range(max(top, 0), min(top + BLOCK, height)):
                for x in range(left, min(left + BLOCK, width)):
                    out[y][x] = (colour[0], colour[1], colour[2], 255)
    return out


DIRECTIONS = ['north', 'north-east', 'east', 'south-east',
              'south', 'west', 'north-west']
WALK_FRAMES = 8


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'sprites/player'

    jobs = [(f'{root}/myth/{d}.png', f'{root}/rumour/stand/{d}.png')
            for d in DIRECTIONS]
    jobs += [(f'{root}/myth/frame_{i:03d}.png',
              f'{root}/rumour/walk/frame_{i:03d}.png')
             for i in range(WALK_FRAMES)]

    for source, target in jobs:
        width, height, pixels = read_png(source)
        write_png(target, width, height, reduce_sprite(pixels, width, height))
        print(f'  {source} -> {target}')

    print(f'{len(jobs)} files written')


if __name__ == '__main__':
    main()
