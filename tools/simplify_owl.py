#!/usr/bin/env python3
"""Flatten the owl art to an 8-colour palette with traveller-style eyes.

    python3 tools/simplify_owl.py sprites/owl/myth

Run this after regenerating any owl sprite. It rewrites the files IN PLACE;
git history is the record of what the generator produced.

WHY: PixelLab returns smooth, heavily-shaded art -- 143 distinct colours
across the owl's eleven east-facing frames, most of them near-duplicate
shades forming gradients. The traveller's own art is far flatter: 24 colours,
39% of it one flat black outline plus two flat body tones. Beside him the owl
read as rendered rather than pixelled.

Two reductions, both derived from the art rather than invented:

  PALETTE  every pixel snaps to the 8 most-used colours, computed ACROSS ALL
           FRAMES AT ONCE so no frame invents its own shading. The amber iris
           is a minority colour and drops out, which is what turns the eyes
           into dots for free.

  EYES     the snap alone leaves mid-tones inside the eye, which reads as a
           smudge. The traveller has none: his eye is a pale block with a dark
           pupil and nothing between. Each eye is binarised to match.

Note the owl's amber eyes and its orange beak are THE SAME HUE, so no colour
rule can keep one and drop the other. Dropping both is deliberate: it matches
the traveller, whose eyes carry no iris colour either.

Standard library only, for the same reason build_rumour.py is.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_rumour import read_png, write_png  # noqa: E402

COLOURS = 8

# Two colours closer than this are the same tone as far as the eye is
# concerned, and letting both into the palette wastes a slot. Without this the
# top eight by raw frequency came back as FIVE near-identical blacks
# (#000007, #01000a, #010005, #000008 ...) and the owl lost its whole light
# range. Squared distance, so 26 apart in RGB.
MIN_SEPARATION = 26 ** 2

# The poses Assets actually references. flying/ and flapping-wings/ are the
# superseded two-frame beat -- including them dragged the palette towards
# their darker distribution.
POSE_DIRS = ('idle', 'soaring', 'wingbeat')

# A pale run bigger than this is the chest patch, not an eye.
MAX_EYE = 13

# Eyes live in the top of the figure; the chest patch does not.
HEAD_FRACTION = 0.62

# Inside an eye, anything brighter than this becomes the disc, the rest ink.
EYE_SPLIT = 110


def luminance(colour):
    return 0.299 * colour[0] + 0.587 * colour[1] + 0.114 * colour[2]


def owl_frames(root):
    """Every owl sprite in a pose Assets uses, so the palette is shared."""
    frames = []
    for pose in POSE_DIRS:
        for directory, _, names in os.walk(os.path.join(root, pose)):
            for name in sorted(names):
                if name.endswith('.png'):
                    frames.append(os.path.join(directory, name))
    return sorted(frames)


def shared_palette(paths, count):
    """The most-used colours, but no two closer than MIN_SEPARATION.

    Taking the top N by frequency alone does not work here: the art carries
    several near-identical blacks, each common enough to claim a slot, which
    leaves nothing for the light end. Walking the list in frequency order and
    skipping anything too close to a colour already chosen keeps the palette
    spread across the whole tonal range.
    """
    counts = {}
    for path in paths:
        width, height, pixels = read_png(path)
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[y][x]
                if a >= 8:
                    counts[(r, g, b)] = counts.get((r, g, b), 0) + 1

    chosen = []
    for colour, _ in sorted(counts.items(), key=lambda kv: -kv[1]):
        if all(sum((c - d) ** 2 for c, d in zip(colour, picked)) >= MIN_SEPARATION
               for picked in chosen):
            chosen.append(colour)
            if len(chosen) == count:
                break
    return chosen, len(counts)


def snap(pixels, width, height, palette):
    """Nearest palette colour, weighted towards green the way the eye is."""
    out = []
    for y in range(height):
        row = []
        for x in range(width):
            r, g, b, a = pixels[y][x]
            if a < 8:
                row.append((0, 0, 0, 0))
                continue
            near = min(palette, key=lambda p:
                       (p[0] - r) ** 2 * 3 + (p[1] - g) ** 2 * 4 + (p[2] - b) ** 2)
            row.append((near[0], near[1], near[2], 255))
        out.append(row)
    return out


def eye_runs(grid, width, height, disc):
    """Connected runs of the palest colour that are small and high up."""
    rows = [y for y in range(height)
            if any(grid[y][x][3] >= 8 for x in range(width))]
    if not rows:
        return []
    head_bottom = rows[0] + int((rows[-1] - rows[0] + 1) * HEAD_FRACTION)

    seen = [[False] * width for _ in range(height)]
    found = []
    for sy in range(height):
        for sx in range(width):
            if seen[sy][sx] or grid[sy][sx][:3] != disc:
                continue
            stack, run = [(sx, sy)], []
            seen[sy][sx] = True
            while stack:
                x, y = stack.pop()
                run.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if (0 <= nx < width and 0 <= ny < height
                            and not seen[ny][nx] and grid[ny][nx][:3] == disc):
                        seen[ny][nx] = True
                        stack.append((nx, ny))

            xs = [p[0] for p in run]
            ys = [p[1] for p in run]
            if (max(ys) <= head_bottom and len(run) >= 4
                    and max(xs) - min(xs) + 1 <= MAX_EYE
                    and max(ys) - min(ys) + 1 <= MAX_EYE):
                found.append((min(xs), max(xs), min(ys), max(ys)))
    return found


def crisp_eyes(grid, width, height, disc, ink):
    for x0, x1, y0, y1 in eye_runs(grid, width, height, disc):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                r, g, b, a = grid[y][x]
                if a < 8:
                    continue
                pick = disc if luminance((r, g, b)) > EYE_SPLIT else ink
                grid[y][x] = (pick[0], pick[1], pick[2], 255)
    return grid


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'sprites/owl/myth'
    frames = owl_frames(root)
    palette, before = shared_palette(frames, COLOURS)
    disc = max(palette, key=luminance)
    ink = min(palette, key=luminance)

    print(f'{before} colours -> {len(palette)} across {len(frames)} frames')
    print('  palette: ' + ' '.join('#%02x%02x%02x' % c for c in palette))
    print(f'  disc #%02x%02x%02x   ink #%02x%02x%02x' % (disc + ink))

    for path in frames:
        width, height, pixels = read_png(path)
        grid = snap(pixels, width, height, palette)
        grid = crisp_eyes(grid, width, height, disc, ink)
        write_png(path, width, height, grid)

    print(f'{len(frames)} frames rewritten')


if __name__ == '__main__':
    main()
