# Bit-Depth Fidelity System — Design

Date: 2026-08-25
Status: approved for planning
Branch: `dev`

## Context

*Magics* renders its world at two fidelities. Low fidelity is **myth** — the
crude, dramatised version of events the traveller tells himself. High fidelity
is **truth** — what actually happened. Repairing a gold seam resolves myth into
truth. This is not decoration and not a reward tier; it is the mechanism by
which the story is told.

The existing prototype is a gray-box of a *retired* design: an adversarial enemy
that strips a power-up on contact. Its movement, throw arc and depth rendering
are sound and reusable; its framing is not.

### Why this slice first

The full story document describes at least seven subsystems that do not exist
(fidelity rendering, manipulation verbs, animals, the pattern/puzzle loop, owl
dialogue, ambient life, world structure). That is too much for one spec.

Fidelity is specced first because it is the only subsystem that dictates **how
every asset in the game must be authored**. Discovering its requirements after
commissioning art would be expensive. It is also testable against the scene that
already exists.

## Decisions

| Decision | Choice | Rejected alternatives |
|---|---|---|
| Scope of change | **Spatial** — fidelity is a property of place | Global (whole world steps at once); split character/world |
| Zone geometry | **Authored regions** with rect bounds | Radial zones (needs per-pixel masking, unproven in DragonRuby); per-object (ground cannot participate) |
| Tiers per region | **Binary** — `:myth` or `:truth` | Multi-tier (N× background art, each step lands softer) |
| Traveller's tier | **Derived from the region he stands in** | Monotonic by seams repaired (N× walk cycles); never changes (contradicts the design) |
| Art pipeline | **Both tiers hand-authored** | Build-time derivation; runtime derivation |
| Architecture | **Tier is a rendering concern** | Tier as entity state; region-owned render passes |

### Why hand-authored art, despite the cost

A derivation script can only make the true image *coarser*. In this design myth
is not a degraded truth, it is a **distorted** one — a mythologised deer may have
the wrong number of antlers. Only hand-authoring can express that, and the
distinction is the entire premise of the mechanic.

Consequence: the two tiers of an asset may differ in canvas size, proportions,
foot placement and frame count. Sprite geometry is therefore **per-tier data**,
not per-entity constants.

### Why region-owned render passes were rejected

Regions owning their own draw calls would naturally support per-region
backdrops, but it **breaks global depth sorting**: entities in different regions
must still interleave correctly by depth. Depth sorting is the foundation of the
2.5D presentation and is not negotiable.

## Architecture

Three new modules. No existing module changes responsibility.

### `app/regions.rb`

Owns spatial definition and tier lookup.

Definitions are constants; resolution is runtime state. This split is
deliberate: DragonRuby's hot-reload does not reset `args.state`, and changing
the *shape* of stored entities mid-session has already blanked the screen once
in this project. Region definitions can therefore be retuned live with no state
migration, because the only thing stored is a list of symbols.

```ruby
REGIONS = [
  { name: :east_clearing, x: 640, depth: 0, w: 640, h: 150 },
  { name: :fern_hollow,   x: 0,   depth: 0, w: 640, h: 150 }
]
```

A region declares only its name and bounds. It carries no reference to what
resolves it: resolution is triggered by position (`Regions.at`), so no
cross-reference table is needed and nothing in this slice depends on the
puzzle-loop data model that does not exist yet.

Bounds reuse the footprint convention already established in `world.rb`: `y`
holds **depth**, not screen y. Region membership is therefore the same kind of
test as `World.overlap?`, and no new spatial concept enters the codebase.

Public interface:

- `Regions.at(x, depth)` → region hash (never nil)
- `Regions.tier_at(x, depth)` → `:myth` or `:truth`
- `Regions.resolve!(args, name)` → marks a region resolved
- `Regions.resolved?(args, name)` → boolean
- `Regions.screen_bounds(region)` → screen-space rect for drawing the region's ground
- `Regions.assert_no_overlap!` → raises at startup on overlapping bounds

Totality rules:

- Regions **may not overlap**. Overlap makes lookup order-dependent, producing
  "the tier is wrong sometimes" bugs. A startup assertion refuses to run instead.
- Any point not inside a defined region belongs to `:wilds`, a permanent-myth
  fallback. `tier_at` never returns nil, so regions can be authored
  incrementally without crashing the renderer on bare ground.

State: `args.state.resolved_regions`, an array of symbols, defaulting to `[]`.

### `app/assets.rb`

Maps `(sprite_name, tier)` to files and geometry.

```ruby
ASSETS = {
  player_walk: {
    myth:  { dir: 'sprites/player/myth',  frames: 8, canvas: 40, figure_h: 26, foot_pad: 7 },
    truth: { dir: 'sprites/player/truth', frames: 8, canvas: 64, figure_h: 44, foot_pad: 9 }
  }
}
```

Frame paths are precomputed per tier at load, with manual zero-padding rather
than `format`/`rjust` — this is mruby, and its stdlib coverage is verified
rather than assumed.

Public interface:

- `Assets.descriptor(name, tier)` → descriptor hash
- `Assets.frame_path(name, tier, progress)` → path for a normalised progress
- `Assets.foot_pad_ratio(name, tier)` → `foot_pad / canvas`

**Fallback:** if a tier is not authored for an asset, `descriptor` returns the
`:myth` descriptor and logs once per asset name. This lets regions and puzzles
be built before all truth art exists; a resolved region simply does not change
appearance yet. The log ensures this is never silent.

### `app/scene.rb` (extended)

`Scene.ground` stops drawing one full-width band and draws **one patch per
region**, coloured by that region's tier.

A region rect in `(x, depth)` maps to a plain screen rectangle — the depth→y
mapping is linear and there is no horizontal foreshortening, so no trapezoid
projection is required:

`Regions.screen_bounds` owns this conversion, not `Scene` — it is region
geometry, and `Scene` merely consumes it. The name deliberately differs from
`World.screen_rect`, which converts a single entity and is a different operation:

```ruby
def self.screen_bounds region
  near = World.ground_y region[:depth]
  far  = World.ground_y region[:depth] + region[:h]
  { x: region[:x], y: near, w: region[:w], h: far - near }
end
```

Sky and horizon remain global; they are above the ground plane and not
region-specific.

When painterly backdrops are authored, the colour fill is replaced by a
`sprite:` on the region, using the same asset table and the same code path. If
horizontal foreshortening is ever introduced, `Regions.screen_bounds` is the only
function that changes.

## Data flow

Drawables carry a **sprite name and normalised cycle progress**, never a file
path:

```ruby
{ entity: player, sprite: :player_walk, progress: 0.0..1.0, flip: bool, alpha: int }
```

Per frame, for each drawable:

1. `Regions.tier_at(entity.x, entity.depth)` → tier
2. `Assets.frame_path(sprite, tier, progress)` → path
3. `Assets.foot_pad_ratio(sprite, tier)` → foot inset ratio
4. existing `World.screen_rect` → position and size
5. existing `Renderer.foot_inset` → plant the feet
6. existing `Scene.image` → emit the sprite

Steps 4–6 are unchanged. Depth sorting is untouched: regions determine which
file a drawable resolves to and nothing else.

### Why progress is normalised

`Player` divides `walk_distance` by a fixed cycle length and stops there. It
never learns how many frames exist. `Renderer` multiplies progress by the
descriptor's frame count.

This makes cadence **frame-count independent by construction**. A 4-frame myth
cycle and an 8-frame truth cycle complete over the same ground distance and
animate at the same apparent speed. Had frame distance stayed a fixed constant,
a myth tier with fewer frames would visibly animate at a different rate.

Static sprites omit `progress` and resolve to frame 0. A player who is not
moving reports `progress: 0.0` rather than holding its last value, preserving
the existing behaviour that standing still returns to the neutral frame instead
of freezing mid-stride.

## Changes to existing code

| File | Change |
|---|---|
| `app/renderer.rb` | `push` resolves `sprite:` → path + geometry before existing logic; colour-rectangle branch retained |
| `app/player.rb` | `drawable` returns `sprite:`/`progress:` instead of `path:`; `frame_index` removed |
| `app/config.rb` | `PLAYER_W/H`, `PLAYER_FIGURE_H`, `PLAYER_FOOT_PAD`, `PLAYER_FOOT_PAD_RATIO`, `PLAYER_FRAME_COUNT`, `PLAYER_FRAMES`, `PLAYER_SPRITE_DIR` move to `assets.rb`; `WALK_FRAME_DISTANCE` becomes `WALK_CYCLE_DISTANCE` |
| `app/scene.rb` | `ground` draws one patch per region, via `Regions.screen_bounds` |
| `app/game_state.rb` | `VERSION` bump; `resolved_regions` defaults to `[]` |
| `app/seam.rb` | reaching the seam resolves **the region it stands in** (`Regions.at` on the seam's own position) rather than completing the level |
| `app/main.rb` | requires the new modules; startup overlap assertion |

`config.rb` retains only values tuned by feel — speeds, distances, the depth
range. Sprite measurements were never tuning constants; they describe a specific
PNG and belong beside it.

### Migration

The eight frames in `sprites/player/` are the **myth** tier and move to
`sprites/player/myth/`. No truth art exists yet; the fallback covers this.

### Deliberately not demolished

`enemy.rb`, `rock.rb`, `seam.rb` and `completion.rb` encode the retired
adversarial loop and are **left running** in this slice.

Removing them would leave a stretch with no gameplay and, more practically, the
enemy is the only non-player entity that moves through space — making it the
only available proof that tier lookup works on something other than the player.
A patrolling entity crossing a region boundary and visibly changing tier is
precisely the integration test this slice needs.

Demolition belongs to the next slice, where animals and the manipulation verbs
arrive to replace it.

**Known naming collision:** `seam.rb` currently means "goal object", while in
the new design *seam* means "the thing that resolves a region". Both meanings
coexist for one slice. Renaming is deferred to the puzzle-loop slice to avoid
churn now.

## Authoring tool

A region overlay — outlines and names drawn over the scene — behind
`Config::SHOW_REGIONS`, default `false`.

Region bounds are authored by eye in `(x, depth)` units that correspond to
nothing visible on screen. Unlike a numeric HUD, this displays **spatial**
information that cannot be read any other way, and it is what makes the
hot-reload authoring loop usable. It is scaffolding and is removed once regions
are placed.

## Error handling and guards

| Condition | Behaviour |
|---|---|
| Point outside all regions | Falls back to `:wilds`, permanent myth |
| Overlapping region bounds | Startup assertion raises; game refuses to run |
| Tier not authored for an asset | Returns `:myth` descriptor, logs once per asset |
| Missing frame file | **No runtime guard.** DragonRuby renders nothing for a bad path. Prevented by the asset-existence check in `dev/checks/`, which must be run after any art change |

## Verification

Three tiers, because DragonRuby has no test framework and MRI cannot vouch for
mruby.

**1. Pure-logic harnesses — `dev/checks/`, plain MRI Ruby, no engine:**

- `Regions.at` returns expected regions for a table of known points, including
  `:wilds` fallback points and points exactly on a boundary
- regions do not overlap
- **every path in the asset table exists on disk** — the likeliest real failure
  is a typo or an unauthored tier
- progress → frame index across both an 8-frame and a 4-frame descriptor,
  confirming cadence is frame-count independent

**2. One in-engine smoke run per change.** Boot, assert via `puts`, screenshot,
quit. Deleted before commit.

**MRI passing does not mean mruby works.** This project has direct evidence:
methods with required keyword arguments returned `nil` silently in the engine
while `ruby -c` reported no problem, blanking the entire screen. The harnesses
check logic, not runtime compatibility, and can never be the last word. The
in-engine run is not optional.

**3. One permanent guard in the shipping game:** the region-overlap assertion.

**Human judgement required:** whether the myth/truth transition reads as
intentional, and whether the hard tier cut is acceptable in motion. Screenshots
of both sides of a boundary crossing will be produced, but the call is the
author's.

## Accepted consequences

- The traveller's tier flips the instant his ground-contact point crosses a
  boundary — a hard cut, not a fade. Boundaries are expected to be hidden behind
  tree lines, mist and elevation.
- A region can never surprise the player twice; binary tiers mean one transition
  per area.
- Region boundaries are authored rather than organic.

## Out of scope

Manipulation verbs (push, pick up, throw-to-nudge); animals; the
pattern-completion puzzle loop; owl dialogue; ambient life; world structure and
traversal; the ending. Each gets its own spec.

Open questions 2, 3 and 5 from the story document (what he sought, who waits at
home, how many pattern moments exist) do not constrain this slice and remain
open. Question 4 — what activating a seam changes on screen — is answered here
only for the *rendering* half: the region's ground and its contents change tier.
