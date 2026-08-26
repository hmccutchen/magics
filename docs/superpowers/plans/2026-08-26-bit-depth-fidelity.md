# Bit-Depth Fidelity System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the world at two fidelities — `:myth` and `:truth` — as a property of authored regions of ground, so that resolving a region visibly changes both that ground and anything standing on it.

**Architecture:** Tier is a rendering concern. Two new modules — `Regions` (spatial definition, tier lookup, resolved state) and `Assets` (maps `(sprite_name, tier)` to files and geometry). Entities carry a sprite *name* and normalised cycle progress; they never learn their tier or their file path. Depth sorting is untouched.

**Tech Stack:** DragonRuby GTK 7.15 (mruby), plain Ruby. No test framework exists — verification is plain-MRI logic harnesses in `dev/checks/` plus a mandatory in-engine smoke run per task.

**Spec:** `docs/superpowers/specs/2026-08-25-bit-depth-fidelity-design.md`

## Global Constraints

- **mruby, not MRI.** Methods with required keyword arguments (`def f x:, y:`) silently return `nil` — no exception, no warning. Use positional arguments or keyword arguments with defaults. Never assume a stdlib method exists; `format`, `rjust` and `sprintf` are avoided in favour of plain string operations.
- **`ruby -c` passing proves nothing about the engine.** Every task ends with an in-engine boot.
- **Solid primitives are deprecated in 7.15.** All filled rectangles go through `Scene.solid`, which emits a sprite with `path: :solid`.
- **Everything draws into `args.outputs.sprites`.** Output collections are layered relative to each other, so using a second collection breaks depth sorting.
- **Entities are anchored at their ground contact point** — `(x, depth)` is the feet, horizontally centred.
- **`args.state` survives hot-reload.** Any change to an entity's field set requires bumping `GameState::VERSION`.
- **Regions may not overlap.** Overlap makes lookup order-dependent.
- **No runtime guard exists for a missing sprite file.** DragonRuby renders nothing. `dev/checks/check_assets.rb` must be run after any art change.
- Screen is fixed 1280x720, origin bottom-left. Depth range is `0.0` (nearest) to `300.0` (farthest).

## Plan-level refinement to the spec

The spec says sprite geometry is per-tier but does not state what keeps the character a consistent size. **The drawn size must be derived, not authored**: if myth and truth canvases differ (40px vs 64px), drawing both at a fixed 138px would make the traveller visibly change size when he crosses a boundary — reading as a bug, not a revelation.

So `Config::CHARACTER_HEIGHT_PX = 90` defines the on-screen height of the *figure*, and each tier's draw size is derived from its own measurements:

```
draw_size = canvas * (CHARACTER_HEIGHT_PX / figure_h)
```

This replaces `Config::PLAYER_W`/`PLAYER_H`. Task 3 verifies the figure height is identical across tiers.

## File structure

| File | Responsibility |
|---|---|
| `app/regions.rb` (new) | Region definitions, point lookup, tier lookup, resolved state, screen bounds, overlap guard |
| `app/assets.rb` (new) | `(sprite, tier)` → frame paths and geometry; myth fallback |
| `dev/checks/check_regions.rb` (new) | Pure-logic harness for `Regions` |
| `dev/checks/check_assets.rb` (new) | Pure-logic harness for `Assets`, including on-disk path existence |
| `dev/checks/run_all.rb` (new) | Runs every harness, exits non-zero on failure |
| `app/world.rb` | Gains `World.place`; `screen_rect` delegates to it |
| `app/renderer.rb` | Resolves `sprite:` → path + geometry via `Regions` + `Assets` |
| `app/player.rb` | Emits `sprite:`/`progress:`; loses `frame_index`/`sprite_path` |
| `app/scene.rb` | `ground` draws one patch per region; region overlay |
| `app/config.rb` | Loses sprite measurements; gains `CHARACTER_HEIGHT_PX`, tier colours, `SHOW_REGIONS` |
| `app/seam.rb` | Resolves the region it stands in |
| `app/game_state.rb` | `VERSION` bump; `resolved_regions` default and reset |
| `app/main.rb` | Requires the new modules |

---

### Task 1: Region model and lookup

Pure logic, no engine integration. Deliverable: `Regions` answers "which region is this point in, and what tier is it?" with a passing harness.

**Files:**
- Create: `app/regions.rb`
- Create: `dev/checks/check_regions.rb`
- Create: `dev/checks/run_all.rb`

**Interfaces:**
- Consumes: `Config::SCREEN_W`, `Config::DEPTH_FAR`, `World.ground_y(depth)`
- Produces:
  - `Regions::REGIONS` → array of `{ name:, x:, depth:, w:, h: }`
  - `Regions::WILDS` → the fallback region hash
  - `Regions.at(x, depth)` → region hash, never nil
  - `Regions.tier_at(args, x, depth)` → `:myth` | `:truth`
  - `Regions.resolved?(args, name)` → boolean
  - `Regions.resolve!(args, name)` → nil
  - `Regions.screen_bounds(region)` → `{ x:, y:, w:, h: }` in screen space
  - `Regions.overlapping` → array of `[name, name]` pairs
  - `Regions.assert_no_overlap!` → raises `RuntimeError` on overlap

- [ ] **Step 1: Write the failing harness**

Create `dev/checks/run_all.rb`:

```ruby
# Runs every pure-logic harness under dev/checks.
#
# These run in plain MRI Ruby, NOT in DragonRuby's mruby. They check logic,
# never runtime compatibility -- mruby has silently returned nil from methods
# MRI accepts. Passing here does not mean the game runs. Boot the engine too.
failures = 0

Dir[File.join(__dir__, 'check_*.rb')].sort.each do |path|
  puts "== #{File.basename path}"
  system(RbConfig.ruby, path) || failures += 1
end

puts
puts failures.zero? ? 'ALL CHECKS PASSED' : "#{failures} CHECK FILE(S) FAILED"
exit(failures.zero? ? 0 : 1)
```

Create `dev/checks/check_regions.rb`:

```ruby
require 'rbconfig'
require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'

# Minimal stand-in for DragonRuby's args.state, which is an open structure.
class FakeState
  attr_accessor :resolved_regions
end

class FakeArgs
  attr_reader :state
  def initialize
    @state = FakeState.new
  end
end

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

puts 'regions do not overlap'
check 'overlapping pairs', Regions.overlapping, []

puts 'point lookup'
check 'inside fern_hollow',      Regions.at(100, 50)[:name],   :fern_hollow
check 'inside east_clearing',    Regions.at(1000, 50)[:name],  :east_clearing
check 'inside far_stand',        Regions.at(640, 250)[:name],  :far_stand
check 'corridor gap is wilds',   Regions.at(640, 50)[:name],   :wilds
check 'far corner is far_stand', Regions.at(1279, 299)[:name], :far_stand

puts 'boundaries are half-open (low edge inclusive, high edge exclusive)'
check 'x at left edge',    Regions.at(0, 50)[:name],     :fern_hollow
check 'x one before right', Regions.at(519, 50)[:name],  :fern_hollow
check 'x at right edge',   Regions.at(520, 50)[:name],   :wilds
check 'depth at low edge', Regions.at(100, 0)[:name],    :fern_hollow
check 'depth at high edge', Regions.at(100, 160)[:name], :far_stand

puts 'tier lookup'
args = FakeArgs.new
check 'unresolved is myth', Regions.tier_at(args, 100, 50), :myth
Regions.resolve! args, :fern_hollow
check 'resolved is truth',  Regions.tier_at(args, 100, 50), :truth
check 'neighbour unaffected', Regions.tier_at(args, 1000, 50), :myth
check 'resolved? true',  Regions.resolved?(args, :fern_hollow), true
check 'resolved? false', Regions.resolved?(args, :far_stand),   false

puts 'resolving is idempotent and refuses wilds'
Regions.resolve! args, :fern_hollow
check 'no duplicate', args.state.resolved_regions.count(:fern_hollow), 1
Regions.resolve! args, :wilds
check 'wilds never resolves', Regions.resolved?(args, :wilds), false

puts 'screen bounds'
bounds = Regions.screen_bounds({ name: :t, x: 100, depth: 0, w: 200, h: 150 })
check 'x passes through', bounds[:x], 100
check 'w passes through', bounds[:w], 200
check 'y is ground_y at near edge', bounds[:y], World.ground_y(0)
check 'h spans near to far', bounds[:h], World.ground_y(150) - World.ground_y(0)

puts
puts $failures.zero? ? 'check_regions: PASSED' : "check_regions: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
```

- [ ] **Step 2: Run the harness to verify it fails**

```bash
cd "/Users/hassanmccutchen/Desktop/dragonruby-gtk-macos (1)/dragonruby-macos/mygame"
ruby dev/checks/run_all.rb
```

Expected: FAIL — `cannot load such file -- app/regions.rb`

- [ ] **Step 3: Write `app/regions.rb`**

```ruby
# Regions
#
# The world is divided into authored areas. Each is either myth (the
# dramatised version the traveller tells himself) or truth (what actually
# happened). Repairing a seam resolves one region.
#
# Definitions are constants; resolution is runtime state. That split is
# deliberate: DragonRuby's hot-reload re-evaluates code but does NOT reset
# args.state, and changing the shape of a stored entity mid-session has already
# blanked this game's screen once. Because the only thing stored here is a list
# of symbols, region bounds can be retuned live with no state migration.
#
# Bounds use the same convention as World.footprint: `depth` is the second
# axis, NOT a screen coordinate. Membership is plain arithmetic rather than
# DragonRuby's Geometry mixin, so this module loads unchanged in plain Ruby and
# can be checked outside the engine.
module Regions
  # Anywhere not inside a defined region. Permanently myth, so that regions can
  # be authored incrementally without the renderer hitting a nil tier.
  WILDS = { name: :wilds, x: 0, depth: 0, w: Config::SCREEN_W, h: Config::DEPTH_FAR }

  # Regions may not overlap -- see assert_no_overlap! at the bottom of this file.
  # The corridor between x=520 and x=760 is deliberately left uncovered so the
  # wilds fallback is exercised by the running game, not only by the harness.
  REGIONS = [
    { name: :fern_hollow,   x: 0,   depth: 0,   w: 520,  h: 160 },
    { name: :east_clearing, x: 760, depth: 0,   w: 520,  h: 160 },
    { name: :far_stand,     x: 0,   depth: 160, w: 1280, h: 140 }
  ]

  # Half-open on both axes: the low edge belongs to this region, the high edge
  # belongs to the next. Without that rule a point on a shared border would
  # match two regions and lookup would depend on declaration order.
  def self.contains? region, x, depth
    x >= region[:x] && x < region[:x] + region[:w] &&
      depth >= region[:depth] && depth < region[:depth] + region[:h]
  end

  def self.at x, depth
    REGIONS.each do |region|
      return region if contains? region, x, depth
    end

    WILDS
  end

  def self.resolved_names args
    args.state.resolved_regions ||= []
  end

  def self.resolved? args, name
    resolved_names(args).include? name
  end

  # Reassigns rather than mutating in place, so nothing depends on how
  # args.state hands back a stored array.
  def self.resolve! args, name
    return if name == WILDS[:name]
    return if resolved? args, name

    args.state.resolved_regions = resolved_names(args) + [name]
  end

  def self.tier_at args, x, depth
    resolved?(args, at(x, depth)[:name]) ? :truth : :myth
  end

  # A region rect maps to a plain screen rectangle: the depth->y mapping is
  # linear and there is no horizontal foreshortening, so no trapezoid
  # projection is needed. If foreshortening is ever added, this is the only
  # function that changes.
  #
  # Named to differ from World.screen_rect, which converts a single entity and
  # is a different operation.
  def self.screen_bounds region
    near = World.ground_y region[:depth]
    far  = World.ground_y region[:depth] + region[:h]

    { x: region[:x], y: near, w: region[:w], h: far - near }
  end

  def self.rects_overlap? a, b
    a[:x] < b[:x] + b[:w] && a[:x] + a[:w] > b[:x] &&
      a[:depth] < b[:depth] + b[:h] && a[:depth] + a[:h] > b[:depth]
  end

  def self.overlapping
    pairs = []

    REGIONS.each_with_index do |a, i|
      REGIONS.each_with_index do |b, j|
        next if j <= i

        pairs << [a[:name], b[:name]] if rects_overlap? a, b
      end
    end

    pairs
  end

  # Overlapping bounds make lookup order-dependent, which surfaces as "the tier
  # is wrong sometimes" -- miserable to diagnose. Refuse to start instead.
  # Runs on load, and therefore again on every hot-reload of this file.
  def self.assert_no_overlap!
    bad = overlapping
    return if bad.empty?

    raise "Regions overlap: #{bad.map { |pair| pair.join(' & ') }.join(', ')}"
  end

  assert_no_overlap!
end
```

- [ ] **Step 4: Run the harness to verify it passes**

```bash
ruby dev/checks/run_all.rb
```

Expected: every line `PASS`, ending `ALL CHECKS PASSED`, exit 0.

- [ ] **Step 5: Verify the overlap guard actually fires**

Temporarily add an overlapping region to `REGIONS`:

```ruby
{ name: :bogus, x: 100, depth: 50, w: 100, h: 50 }
```

Run `ruby dev/checks/run_all.rb`. Expected: raises `Regions overlap: fern_hollow & bogus`. **Remove the bogus region and re-run to confirm it passes again.** A guard never seen firing is not known to work.

- [ ] **Step 6: Commit**

```bash
git add app/regions.rb dev/checks/
git commit -m "Add region model with tier lookup and overlap guard"
```

---

### Task 2: Asset table

Deliverable: `Assets` resolves `(sprite, tier)` to a real file and its geometry, falling back to myth for unauthored tiers.

**Files:**
- Create: `app/assets.rb`
- Create: `dev/checks/check_assets.rb`
- Move: `sprites/player/frame_00*.png` → `sprites/player/myth/`

**Interfaces:**
- Consumes: `Config::CHARACTER_HEIGHT_PX` (added by Step 4 of this task, before the harness needs it)
- Produces:
  - `Assets.descriptor(name, tier)` → `{ dir:, frames:, canvas_w:, canvas_h:, figure_h:, foot_pad:, paths: }`
  - `Assets.frame_path(name, tier, progress)` → String
  - `Assets.foot_pad_ratio(name, tier)` → Float
  - `Assets.draw_size(name, tier)` → `[width, height]` Floats

- [ ] **Step 1: Move the existing art to its tier**

The eight frames currently in `sprites/player/` are the **myth** tier.

```bash
cd "/Users/hassanmccutchen/Desktop/dragonruby-gtk-macos (1)/dragonruby-macos/mygame"
mkdir -p sprites/player/myth
git mv sprites/player/frame_000.png sprites/player/frame_001.png \
       sprites/player/frame_002.png sprites/player/frame_003.png \
       sprites/player/frame_004.png sprites/player/frame_005.png \
       sprites/player/frame_006.png sprites/player/frame_007.png \
       sprites/player/myth/
ls sprites/player/myth/
```

Expected: eight files listed.

- [ ] **Step 2: Write the failing harness**

Create `dev/checks/check_assets.rb`:

```ruby
require_relative '../../app/config.rb'
require_relative '../../app/assets.rb'

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

def check_close label, got, want, tolerance = 0.01
  check label, (got - want).abs < tolerance, true
end

# Paths in the table are relative to the game directory, which is two levels up.
GAME_DIR = File.expand_path '../..', __dir__

puts 'every declared frame file exists on disk'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    descriptor[:paths].each do |path|
      check "#{name}/#{tier} #{path}", File.exist?(File.join(GAME_DIR, path)), true
    end
  end
end

puts 'frame count matches declared frames'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    check "#{name}/#{tier} path count", descriptor[:paths].length, descriptor[:frames]
  end
end

puts 'progress maps across the whole cycle'
frames = Assets.descriptor(:player_walk, :myth)[:frames]
check 'progress 0.0',   Assets.frame_path(:player_walk, :myth, 0.0),   'sprites/player/myth/frame_000.png'
check 'progress 0.5',   Assets.frame_path(:player_walk, :myth, 0.5),   "sprites/player/myth/frame_00#{frames / 2}.png"
check 'progress 0.99',  Assets.frame_path(:player_walk, :myth, 0.99),  "sprites/player/myth/frame_00#{frames - 1}.png"
check 'progress 1.0 clamps', Assets.frame_path(:player_walk, :myth, 1.0), "sprites/player/myth/frame_00#{frames - 1}.png"

puts 'unauthored tier falls back to myth'
check 'truth falls back', Assets.descriptor(:player_walk, :truth), Assets.descriptor(:player_walk, :myth)

puts 'geometry'
check_close 'foot pad ratio', Assets.foot_pad_ratio(:player_walk, :myth), 7.0 / 40

w, h = Assets.draw_size :player_walk, :myth
check_close 'draw width',  w, 138.46
check_close 'draw height', h, 138.46

puts 'figure height is identical across every declared tier'
Assets::TABLE.each do |name, tiers|
  tiers.each_key do |tier|
    _, drawn_h = Assets.draw_size name, tier
    descriptor = Assets.descriptor name, tier
    figure_px  = drawn_h * descriptor[:figure_h] / descriptor[:canvas_h]
    check_close "#{name}/#{tier} figure px", figure_px, Config::CHARACTER_HEIGHT_PX
  end
end

puts
puts $failures.zero? ? 'check_assets: PASSED' : "check_assets: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
```

- [ ] **Step 3: Run it to verify it fails**

```bash
ruby dev/checks/run_all.rb
```

Expected: FAIL — `cannot load such file -- app/assets.rb`

- [ ] **Step 4: Add `CHARACTER_HEIGHT_PX` to `app/config.rb`**

Insert immediately above the existing `SPRITE_CANVAS` line (the surrounding sprite measurements are removed in Task 3):

```ruby
  # On-screen height of the character FIGURE at full scale, in pixels. Each
  # tier's drawn canvas size is derived from this and that tier's own
  # measurements, so the traveller stays the same apparent size no matter which
  # tier he is rendered at. Without this he would visibly resize when crossing
  # a region boundary, which reads as a bug rather than a revelation.
  CHARACTER_HEIGHT_PX = 90
```

- [ ] **Step 5: Write `app/assets.rb`**

```ruby
# Assets
#
# Maps a sprite name and a fidelity tier to real files and their geometry.
#
# The two tiers of an asset are hand-authored and may differ in canvas size,
# proportions, frame count and foot placement -- myth is a DISTORTED version of
# the truth, not merely a coarser one, so a mythologised creature may be the
# wrong shape entirely. Geometry therefore belongs beside each file rather than
# in Config, which keeps only values tuned by feel.
module Assets
  # Tier used when an asset has no entry for the requested tier.
  FALLBACK_TIER = :myth

  # Declare a tier only once its art exists. An undeclared tier falls back to
  # myth, which is what lets regions and puzzles be built before the truth art
  # is authored -- a resolved region simply does not change appearance yet.
  ASSETS = {
    player_walk: {
      myth: {
        dir: 'sprites/player/myth',
        frames: 8,
        canvas_w: 40,
        canvas_h: 40,
        figure_h: 26,   # visible figure height within the canvas
        foot_pad: 7     # transparent rows below the feet
      }
    }
  }

  # Zero-padded by hand rather than with format/rjust: this runs in mruby, which
  # has already silently returned nil from a method MRI accepted. Stdlib
  # coverage is verified, not assumed.
  def self.frame_paths dir, count
    (0...count).map do |index|
      padded = index.to_s
      padded = "0#{padded}" while padded.length < 3
      "#{dir}/frame_#{padded}.png"
    end
  end

  # Paths are built once at load rather than per frame, to avoid allocating
  # strings at 60fps.
  TABLE = {}
  ASSETS.each do |name, tiers|
    TABLE[name] = {}

    tiers.each do |tier, descriptor|
      TABLE[name][tier] = descriptor.merge({ paths: frame_paths(descriptor[:dir], descriptor[:frames]) })
    end
  end

  @warned = {}

  def self.descriptor name, tier
    tiers = TABLE[name]
    raise "Unknown sprite: #{name}" unless tiers
    return tiers[tier] if tiers[tier]

    warn_missing name, tier
    tiers[FALLBACK_TIER]
  end

  # Logged once per sprite/tier pair so an unauthored tier is visible in the
  # log without spamming it 60 times a second.
  def self.warn_missing name, tier
    key = "#{name}/#{tier}"
    return if @warned[key]

    @warned[key] = true
    puts "[Assets] #{name} has no #{tier} tier; falling back to #{FALLBACK_TIER}"
  end

  # `progress` is a normalised 0.0..1.0 position through the animation cycle.
  # The caller never learns how many frames a tier has, which is what makes
  # cadence identical across tiers with differing frame counts.
  def self.frame_path name, tier, progress
    paths = descriptor(name, tier)[:paths]

    index = (progress * paths.length).to_i
    index = 0 if index < 0
    index = paths.length - 1 if index >= paths.length

    paths[index]
  end

  # Fraction of the drawn height that is empty canvas beneath the feet.
  def self.foot_pad_ratio name, tier
    found = descriptor name, tier
    found[:foot_pad].to_f / found[:canvas_h]
  end

  # Drawn canvas size at full scale, derived so the FIGURE lands at
  # Config::CHARACTER_HEIGHT_PX regardless of how the tier was authored.
  def self.draw_size name, tier
    found  = descriptor name, tier
    factor = Config::CHARACTER_HEIGHT_PX.to_f / found[:figure_h]

    [found[:canvas_w] * factor, found[:canvas_h] * factor]
  end
end
```

- [ ] **Step 6: Run the harness to verify it passes**

```bash
ruby dev/checks/run_all.rb
```

Expected: `ALL CHECKS PASSED`. The fallback check confirms `:truth` returns the myth descriptor; one `[Assets]` line is printed.

- [ ] **Step 7: Commit**

```bash
git add app/assets.rb app/config.rb dev/checks/check_assets.rb sprites/
git commit -m "Add asset table keyed by sprite name and fidelity tier"
```

---

### Task 3: Resolve sprites through region tier

Deliverable: the running game draws the player through `Regions` + `Assets`. Nothing looks different yet — the point is that the path is now resolved by tier.

**Files:**
- Modify: `app/world.rb` (add `place`, delegate `screen_rect`)
- Modify: `app/renderer.rb` (`push` splits into sprite and colour branches)
- Modify: `app/player.rb` (`drawable` emits `sprite:`/`progress:`)
- Modify: `app/config.rb` (remove sprite measurements, rename cycle constant)
- Modify: `app/game_state.rb` (`VERSION` bump, `resolved_regions`)
- Modify: `app/main.rb` (requires)

**Interfaces:**
- Consumes: `Regions.tier_at(args, x, depth)`, `Assets.draw_size`, `Assets.frame_path`, `Assets.foot_pad_ratio`
- Produces:
  - `World.place(x, depth, w, h, lift = 0)` → `{ x:, y:, w:, h: }`
  - `Player.drawable(args)` → `{ entity:, sprite:, progress:, flip:, alpha: }`
  - `Player.cycle_progress(args)` → Float `0.0..1.0`

- [ ] **Step 1: Add `World.place` and delegate `screen_rect`**

In `app/world.rb`, replace the body of `screen_rect` with a delegation and add `place` above it:

```ruby
  # Converts a ground position and an UNSCALED size into the screen rectangle
  # DragonRuby draws. Split out from screen_rect because a sprite's drawn size
  # comes from its tier descriptor rather than from the entity, so the caller
  # supplies w and h directly.
  def self.place x, depth, w, h, lift = 0
    s = scale depth

    drawn_w = w * s
    drawn_h = h * s

    {
      x: x - (drawn_w / 2.0),   # x is the entity's centre, so back off half
      y: ground_y(depth) + lift,
      w: drawn_w,
      h: drawn_h
    }
  end

  def self.screen_rect entity, lift = 0
    place entity.x, entity.depth, entity.w, entity.h, lift
  end
```

- [ ] **Step 2: Rewrite `Renderer.push`**

In `app/renderer.rb`, replace `push` and delete `foot_inset` entirely:

```ruby
  def self.push args, drawable
    if drawable[:sprite]
      push_sprite args, drawable
    else
      push_solid args, drawable
    end
  end

  # Resolves the drawable's sprite name to a file through the tier of the region
  # its ground position falls in. Entities never learn their own tier: fidelity
  # is a property of place, and place is the renderer's business.
  def self.push_sprite args, drawable
    entity = drawable[:entity]
    name   = drawable[:sprite]
    tier   = Regions.tier_at args, entity.x, entity.depth

    width, height = Assets.draw_size name, tier
    rect  = World.place entity.x, entity.depth, width, height, (drawable[:lift] || 0)

    # Push the sprite DOWN so its feet, rather than its canvas bottom, land on
    # the ground plane. Scales with drawn size, so the character stays planted
    # at every depth instead of drifting upward as it grows.
    inset = rect[:h] * Assets.foot_pad_ratio(name, tier)

    args.outputs.sprites << Scene.image(
      rect[:x],
      rect[:y] - inset,
      rect[:w],
      rect[:h],
      Assets.frame_path(name, tier, drawable[:progress] || 0.0),
      drawable[:flip],
      drawable[:alpha] || 255
    )
  end

  def self.push_solid args, drawable
    rect = World.screen_rect drawable[:entity], (drawable[:lift] || 0)

    args.outputs.sprites << Scene.solid(
      rect[:x], rect[:y], rect[:w], rect[:h], drawable[:color]
    )
  end
```

- [ ] **Step 3: Rewrite `Player.drawable` and the cycle maths**

In `app/player.rb`:

Replace `drawable`, and delete `sprite_path` and `frame_index`:

```ruby
  # Everything the renderer needs to draw the player this frame. Deliberately
  # carries a sprite NAME and a normalised cycle position, never a file path
  # and never a tier -- the renderer resolves both from where the player is
  # standing. This is also what makes cadence independent of frame count: a
  # 4-frame myth cycle and an 8-frame truth cycle cover the same ground.
  def self.drawable args
    {
      entity: args.state.player,
      sprite: :player_walk,
      progress: cycle_progress(args),
      flip: args.state.player.heading_x < 0,
      alpha: alpha(args)
    }
  end

  # Position through the walk cycle, 0.0 to 1.0. Standing still reports 0.0
  # rather than holding its last value, so an idle player returns to the
  # neutral frame instead of freezing mid-stride.
  def self.cycle_progress args
    player = args.state.player
    return 0.0 unless player.moving

    player.walk_distance / Config::WALK_CYCLE_DISTANCE
  end
```

In `accumulate_distance`, replace the cycle calculation:

```ruby
    cycle = Config::WALK_CYCLE_DISTANCE
    player.walk_distance = (player.walk_distance + moved) % cycle
```

In `defaults`, delete the two lines assigning `player.w` and `player.h` from `Config::PLAYER_W`/`PLAYER_H` — a sprite's drawn size now comes from its tier descriptor. Leave `fw`/`fd` alone; the footprint is gameplay, not art.

- [ ] **Step 4: Update `app/config.rb`**

Delete these constants entirely — they were measurements of a specific PNG and now live in `assets.rb`:

`SPRITE_CANVAS`, `PLAYER_FIGURE_H`, `PLAYER_FOOT_PAD`, `PLAYER_W`, `PLAYER_H`, `PLAYER_FOOT_PAD_RATIO`, `PLAYER_SPRITE_DIR`, `PLAYER_FRAME_COUNT`, `PLAYER_FRAMES`.

Replace `WALK_FRAME_DISTANCE = 20.0` with:

```ruby
  # Ground covered by ONE FULL walk cycle. Previously this was distance per
  # frame, which broke as soon as tiers could have different frame counts: a
  # 4-frame cycle would have completed in half the distance and animated at a
  # visibly different speed. Expressing the whole cycle makes cadence identical
  # across tiers by construction.
  WALK_CYCLE_DISTANCE = 160.0
```

Add tier colours beside the existing palette:

```ruby
  COLOR_GROUND_MYTH  = [52, 56, 68]
  COLOR_GROUND_TRUTH = [86, 96, 82]
```

- [ ] **Step 5: Update `app/game_state.rb`**

Bump the version and add the new state key:

```ruby
  VERSION = 9
```

In `ensure_current!`, alongside the existing `args.state.mode ||= :playing`:

```ruby
    # Which regions have been resolved. A plain list of symbols, so unlike an
    # entity it has no shape that can drift across a hot-reload.
    args.state.resolved_regions ||= []
```

In `restart!`, after `args.state.mode = :playing`:

```ruby
    args.state.resolved_regions = []
```

- [ ] **Step 6: Update `app/main.rb` requires**

**Deliberate divergence from the spec:** the spec's changes table puts the
startup overlap assertion in `main.rb`. It is instead called at the bottom of
`regions.rb`'s module body (Task 1). Module bodies re-execute on hot-reload, so
this re-checks every time region bounds are edited — which is exactly when an
overlap gets introduced. A `main.rb` tick-zero check would only fire on a full
restart, missing the case it exists to catch.

Add after `require 'app/world.rb'`:

```ruby
require 'app/regions.rb'
require 'app/assets.rb'
```

`regions.rb` needs `Config` and `World`; `assets.rb` needs `Config`. Both must load after them and before `player.rb`, `renderer.rb` and `scene.rb`.

- [ ] **Step 7: Run the pure-logic harnesses**

```bash
ruby dev/checks/run_all.rb
```

Expected: `ALL CHECKS PASSED`.

- [ ] **Step 8: In-engine smoke run**

Back up `app/main.rb`, then append this probe inside `Main#render`, at the end:

```ruby
    probe args
  end

  def probe args
    t = args.state.tick_count
    pl = args.state.player

    if t == 40
      puts "[P] region=#{Regions.at(pl.x, pl.depth)[:name]} tier=#{Regions.tier_at(args, pl.x, pl.depth)}"
      puts "[P] path=#{Assets.frame_path(:player_walk, Regions.tier_at(args, pl.x, pl.depth), 0.0)}"
      w, h = Assets.draw_size :player_walk, :myth
      puts "[P] draw_size=#{w.round(1)}x#{h.round(1)} (expect 138.5x138.5)"
      pl.moving = true
      pl.walk_distance = 80.0
      puts "[P] progress at half cycle=#{Player.cycle_progress(args).round(3)} (expect 0.5)"
      pl.moving = false
      puts "[P] idle progress=#{Player.cycle_progress(args)} (expect 0.0)"
      Regions.resolve! args, :fern_hollow
      puts "[P] after resolve, fern tier=#{Regions.tier_at(args, 100, 50)} (expect truth)"
      puts "[P] fallback path=#{Assets.frame_path(:player_walk, :truth, 0.0)} (expect myth path)"
    end

    args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: 'smoke.png' } if t == 60
    $gtk.request_quit if t == 70
  end
```

Run it:

```bash
cd "/Users/hassanmccutchen/Desktop/dragonruby-gtk-macos (1)/dragonruby-macos"
rm -f mygame/smoke.png logs/puts.log && rm -rf logs/exceptions
./dragonruby mygame >/dev/null 2>&1 &
sleep 10; pkill -f "dragonruby mygame"; sleep 1
grep "^\[P\]" logs/puts.log
ls logs/exceptions 2>/dev/null || echo "(no exceptions)"
```

Expected: no exceptions, `draw_size=138.5x138.5`, `progress at half cycle=0.5`, `idle progress=0.0`, `fern tier=truth`, and the truth path falling back to `sprites/player/myth/frame_000.png`. Open `smoke.png` and confirm the player still renders exactly as before.

- [ ] **Step 9: Remove the probe and re-verify**

Restore `app/main.rb` from the backup. Re-run the engine for 9 seconds and confirm `logs/exceptions` is absent. Confirm no diagnostics remain:

```bash
grep -rn "probe\|request_quit\|screenshots\|\[P\]" mygame/app/*.rb || echo "(none)"
rm -f mygame/smoke.png
```

- [ ] **Step 10: Commit**

```bash
git add app/
git commit -m "Resolve player sprite through the tier of the region it stands in"
```

---

### Task 4: Draw ground per region, coloured by tier

Deliverable: region boundaries and tiers are visible on screen.

**Files:**
- Modify: `app/scene.rb`

**Interfaces:**
- Consumes: `Regions::REGIONS`, `Regions::WILDS`, `Regions.screen_bounds`, `Regions.resolved?`
- Produces: no new public interface

- [ ] **Step 1: Replace `Scene.ground`**

```ruby
  # One patch per region, coloured by that region's tier, over a wilds-coloured
  # base that fills any ground not covered by a defined region.
  #
  # Drawn base-first: regions never overlap each other, but they do sit on top
  # of the wilds fill, which is what lets regions be authored incrementally
  # without leaving holes in the world.
  #
  # When painterly backdrops are authored this colour fill becomes a sprite on
  # the region, resolved through the same asset table -- same code path.
  def self.ground args
    fill args, Regions::WILDS, Config::COLOR_GROUND_MYTH

    Regions::REGIONS.each do |region|
      tier  = Regions.resolved?(args, region[:name]) ? :truth : :myth
      color = tier == :truth ? Config::COLOR_GROUND_TRUTH : Config::COLOR_GROUND_MYTH

      fill args, region, color
    end
  end

  def self.fill args, region, color
    bounds = Regions.screen_bounds region

    args.outputs.sprites << solid(
      bounds[:x], bounds[:y], bounds[:w], bounds[:h], color
    )
  end
```

`Scene.render` already calls `ground args`; no change needed there. Note `ground` now takes the args it was already being passed.

- [ ] **Step 2: In-engine smoke run**

Append a probe to `Main#render` that resolves one region so both tiers are on screen at once:

```ruby
    if args.state.tick_count == 30
      Regions.resolve! args, :fern_hollow
      puts "[P] resolved fern_hollow"
    end
    args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: 'ground.png' } if args.state.tick_count == 50
    $gtk.request_quit if args.state.tick_count == 60
```

Run the engine as in Task 3, Step 8.

Expected in `ground.png`: the left third of the ground band is the truth colour, the rest is myth, and the uncovered corridor between x=520 and x=760 is myth. Confirm `logs/exceptions` is absent.

- [ ] **Step 3: Remove the probe, re-verify, commit**

Restore `main.rb`, re-run, confirm no exceptions and no leftover diagnostics.

```bash
rm -f mygame/ground.png
git add app/scene.rb
git commit -m "Draw ground as one patch per region, coloured by tier"
```

---

### Task 5: Reaching the seam resolves its region

Deliverable: the whole system works end to end from gameplay — collect the item, walk to the seam, watch the ground resolve.

**Files:**
- Modify: `app/seam.rb`

**Interfaces:**
- Consumes: `Regions.at`, `Regions.resolve!`
- Produces: no new public interface

- [ ] **Step 1: Replace `Seam.check_reached`**

```ruby
  # Reaching a visible seam resolves the region the SEAM stands in -- not the
  # region the player stands in, so the outcome does not depend on which side
  # of a boundary the player approached from.
  #
  # Temporary wiring: the real trigger is the pattern-completion loop, which is
  # a later slice. This exercises the fidelity system end to end without having
  # to build the puzzle mechanic first.
  def self.check_reached args
    return unless visible? args
    return unless World.overlap? args.state.player, args.state.seam

    seam = args.state.seam
    Regions.resolve! args, Regions.at(seam.x, seam.depth)[:name]
  end
```

The seam sits at `x: 1000, depth: 250`, which falls inside `:far_stand`.

**Note:** this removes the only assignment of `args.state.mode = :complete`, so `Completion` becomes unreachable. That is expected — the win state belonged to the retired adversarial design. `completion.rb` is left in place and is demolished in the slice that replaces the loop.

- [ ] **Step 2: In-engine smoke run**

Append a probe that drives the player through the sequence without needing input:

```ruby
    t = args.state.tick_count
    pl = args.state.player

    if t == 30
      pl.x = Config::ITEM_X; pl.depth = Config::ITEM_DEPTH
    end
    if t == 50
      puts "[P] carrying=#{pl.carrying} (expect true)"
      puts "[P] far_stand before=#{Regions.resolved?(args, :far_stand)} (expect false)"
      pl.x = Config::SEAM_X; pl.depth = Config::SEAM_DEPTH
    end
    if t == 70
      puts "[P] far_stand after=#{Regions.resolved?(args, :far_stand)} (expect true)"
      puts "[P] tier at seam=#{Regions.tier_at(args, Config::SEAM_X, Config::SEAM_DEPTH)} (expect truth)"
      args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: 'resolved.png' }
    end
    $gtk.request_quit if t == 90
```

Expected: `carrying=true`, `far_stand before=false`, `far_stand after=true`, `tier at seam=truth`, no exceptions. In `resolved.png` the far band of ground is the truth colour.

- [ ] **Step 3: Remove the probe, re-verify, commit**

```bash
rm -f mygame/resolved.png
git add app/seam.rb
git commit -m "Reaching the seam resolves the region it stands in"
```

---

### Task 6: Region overlay authoring tool

Deliverable: region bounds can be placed by eye, hot-reloading as they are edited.

**Files:**
- Modify: `app/config.rb` (add flag)
- Modify: `app/scene.rb` (add overlay)

**Interfaces:**
- Consumes: `Regions::REGIONS`, `Regions.screen_bounds`, `Regions.resolved?`
- Produces: no new public interface

- [ ] **Step 1: Add the flag to `app/config.rb`**

```ruby
  # Draws region outlines and names over the scene. Authoring tool, not a HUD:
  # region bounds are written in (x, depth) units that correspond to nothing
  # visible on screen, and unlike a numeric readout this shows SPATIAL
  # information that cannot be read any other way. Delete once regions are
  # placed.
  SHOW_REGIONS = false
```

- [ ] **Step 2: Add the overlay to `app/scene.rb`**

Add to the end of `Scene.render`:

```ruby
    region_overlay args if Config::SHOW_REGIONS
```

And the method:

```ruby
  # Outlines each region and labels it. Drawn as four thin solids per region
  # rather than a border primitive, so it stays in args.outputs.sprites and
  # cannot disturb the single-collection ordering the depth sort depends on.
  def self.region_overlay args
    Regions::REGIONS.each do |region|
      bounds = Regions.screen_bounds region
      color  = Regions.resolved?(args, region[:name]) ? Config::COLOR_BANNER : Config::COLOR_HORIZON

      outline args, bounds, color

      args.outputs.labels << {
        x: bounds[:x] + 8,
        y: bounds[:y] + bounds[:h] - 8,
        text: region[:name].to_s,
        size_px: 16,
        **rgb(color)
      }
    end
  end

  def self.outline args, bounds, color
    thickness = 2

    args.outputs.sprites << solid(bounds[:x], bounds[:y], bounds[:w], thickness, color)
    args.outputs.sprites << solid(bounds[:x], bounds[:y] + bounds[:h] - thickness, bounds[:w], thickness, color)
    args.outputs.sprites << solid(bounds[:x], bounds[:y], thickness, bounds[:h], color)
    args.outputs.sprites << solid(bounds[:x] + bounds[:w] - thickness, bounds[:y], thickness, bounds[:h], color)
  end
```

- [ ] **Step 3: In-engine smoke run with the flag on**

Temporarily set `SHOW_REGIONS = true`, add a screenshot probe at tick 50, and run.

Expected: three labelled outlined rectangles; the corridor between `fern_hollow` and `east_clearing` visibly uncovered. Confirm no exceptions.

- [ ] **Step 4: Set the flag back to `false`, remove the probe, re-verify, commit**

```bash
git add app/config.rb app/scene.rb
git commit -m "Add region overlay authoring tool behind a flag"
```

---

## Done criteria

- `ruby dev/checks/run_all.rb` exits 0
- The engine boots with no entries in `logs/exceptions`
- Collecting the item and reaching the seam turns the far ground band from the myth colour to the truth colour
- No probe code, screenshots or diagnostics remain in `app/`
- `git status` is clean on branch `dev`

## Deliberately not done in this slice

- **Truth-tier art.** No `sprites/player/truth/` exists, so the player's own sprite cannot yet be seen changing tier — the fallback returns myth and logs once. The mechanic is verified through the ground colour and through assertions. When truth art arrives, add a `truth:` entry to `Assets::ASSETS` with its own measurements; no code changes.
- **Demolishing the retired loop.** `enemy.rb`, `rock.rb` and `completion.rb` stay. The patrolling enemy is the only non-player entity that moves through space and is therefore the integration test for tier lookup on something other than the player.
- **Renaming `seam.rb`.** *Seam* means both "goal object" and "region resolver" for one slice. Renamed when the puzzle loop lands.
- Per-region backdrop art, manipulation verbs, animals, the pattern loop, owl dialogue, ambient life, world structure.
