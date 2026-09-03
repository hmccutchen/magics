
# Project: Magics (working title)

A small 2D exploration/discovery game built in DragonRuby (Ruby). Solo
first-time game dev project — I'm an experienced Rails engineer but new to
game development and to DragonRuby specifically.

**Design is actively in flux.** This is early-stage and the mechanics have
already changed direction more than once. Treat anything you read in code
as "current," not "final" — the design doc is the source of truth for
intent, code is just today's implementation of it.

## Where to find the real design context

Read `game-story-draft.md` (in this repo) before making any design-adjacent
decision — not just code style ones. It has the current theme, mechanics,
what's been deliberately retired (and why), and open questions still being
worked out. If something in the code contradicts that doc, ask me rather
than guessing which one is stale.

## How I want to work together

- Build in small, reviewable steps. Stop after each one — don't chain
  several features together before I've seen the first.
- Prefer clear, readable code over clever/compressed code.
- If a decision has real tradeoffs, give me the options and your
  recommendation, and let me decide. Don't pick silently.
- Explain DragonRuby-specific idioms the first time they come up, but don't
  re-explain Ruby basics — I know the language.

## Code principles specific to a project still in flux

These matter more here than they would on a settled codebase, precisely
*because* the design keeps changing:

- **Don't build for content that doesn't exist yet.** No generic "quest
  system" or abstracted "puzzle framework" until there are enough concrete
  puzzles to know what they actually have in common. Build the specific
  thing in front of us; generalize later if a real pattern shows up.
- **Keep positions, targets, and tunable numbers out of buried logic.**
  Object spawn points, push-target positions, throw distances, etc. should
  live somewhere easy to find and change (a constants section, a simple
  data structure) — not scattered as magic numbers inside movement/collision
  code. Design values will get tweaked constantly; that shouldn't require
  digging through logic to do it.
- **Keep placeholder (gray-box) rendering separate from game logic.**
  A pushable object's *behavior* (position, whether it's at its target)
  shouldn't be entangled with *how it's drawn* (a rectangle now, a sprite
  later). Swapping gray boxes for real art later should touch rendering
  code only, not the logic that decides what counts as "solved."
- **Delete retired mechanics cleanly — don't comment them out.** If a
  mechanic is cut or reworked, remove it fully. Git history and the design
  doc's "Retired Ideas" section are the record of what used to exist; dead
  commented-out code in the working files is just noise I'll have to
  re-read every time.
- **Comment the "why" for anything that looks arbitrary.** Especially
  around depth-scaling, collision, and anything tied to a specific design
  decision from the story doc — a future session (or future me) shouldn't
  have to guess whether an odd-looking number is intentional or a bug.
- **Small files over one growing main.rb.** As mechanics accumulate (push,
  throw, creature behavior, seam/pattern logic), split them into separate
  files under a clear naming convention rather than letting one file
  absorb everything.

## Current technical state (update this section as things change)

- Depth-axis (2.5D, Sword & Sworcery-style) movement is working: x-axis +
  depth-axis, with depth affecting draw scale and draw order.
- Animated directional walk cycle is working, using real sprite art
  (PixelLab-generated). The walk cycle is a single SIDE VIEW used for all
  eight directions; the push poses are genuinely directional. Per-direction
  walk art is the biggest outstanding art gap.
- Pushing is animated too: each push pose is a TWO-frame cycle (feet planted,
  then mid-stride) on its own `PUSH_CYCLE_DISTANCE`, so he walks the crate
  along instead of sliding it. The old `Player.push_bob` sine-bounce that
  stood in for footfall is gone. `walk_distance` wraps on a common multiple
  of both cycle lengths so neither skips a frame at the wrap.
- `sprites/player/myth/pushing/south-west.png` is drawn but UNUSED: the base
  set has no planted `south-west.png`, so `PUSH_POSES` still draws south-west
  by mirroring south-east (which mirrors both frames, so it animates).
- No jumping, no gravity -- this is a walking-based game.
- Collision uses ground-plane footprint checks in world (x, depth) space,
  not screen-space.
- Bit-depth fidelity system is in. The tiers are a LADDER, coarsest first:
  `:rumour` (2-bit), `:myth` (8-bit), `:truth` (16-bit). The WORLD climbs it by
  place, a region at a time (`Regions.tier_at`), and that is still the rule for
  everything except one thing.
- The TRAVELLER is that exception: he climbs by progress and carries the result
  everywhere (`Player.tier`). He starts at `:rumour` and steps to `:myth` the
  first time a pattern completes; above that rung, place governs him again as
  before. A drawable may now carry its own `:tier`, which `Renderer.tier_for`
  honours over the ground position -- the player's drawable is the only one
  that does. The step-up hangs off `Seams.revealed?` (permanent), NOT
  `Pattern.complete?` (recomputed live from where the blocks sit, and false
  again if one is shoved back out).
- The `:rumour` player art is DERIVED from the myth art, not drawn: it is a
  BUILD PRODUCT of `tools/build_rumour.py` (`python3 tools/build_rumour.py
  sprites/player`). Re-run it after changing any myth player sprite; never
  hand-edit anything under `sprites/player/rumour/`. Deriving is what keeps
  the two tiers from drifting and what makes the geometry identical rather
  than merely similar -- both cycles now draw at 138.5px, so the step-up
  changes fidelity and nothing else.
- Two reductions, and BOTH matter: four colours (the Game Boy DMG ramp) and
  half the spatial resolution (2x2 blocks vote on one tone). Recolouring alone
  keeps every pixel of 8-bit detail, so resolving would read as a palette swap
  rather than as detail arriving. The luminance cuts (12/88/140) come from the
  8-bit art's own distribution, not even steps -- 38% of its pixels are pure
  black outline and the coat spans 57-83, so even bands put 88% of the figure
  into two tones and it reads as a blob.
- The block grid is anchored to the FIGURE'S FEET, not the canvas. Canvas
  alignment made his feet snap a pixel up and down between frames (~3.5 screen
  px of bob the 8-bit art does not have). Foot anchoring reproduces the
  source's registration exactly -- verified: the derived frames carry the same
  `foot_pad` 7/8/7 pattern the myth frames do.
- There is NO separate idle pose, at either tier. RESTING IS FRAME 0 OF THE
  WALK CYCLE -- `cycle_progress` returns 0.0 when he is not moving, so it
  falls out with no branch. Both tiers rest identically.
- That is a deliberate constraint, not a gap. A directional idle set was tried
  and reverted: seven separate stills genuinely differ in height by up to 4px
  (the hood sits higher in some directions), and `figure_h` sets the SCALE, so
  there is no good option. One shared `figure_h` swings his drawn height
  between ~87 and ~97px as he turns; per-pose `figure_h` holds the height at
  90px but makes the art scale vary 15%, shrinking his whole body and pixel
  size in some directions. Resting on the walk cycle means ONE asset at ONE
  `figure_h`, so nothing can resize him. Verified: a single distinct scale
  (3.462) across resting, walking and pushing, every direction, both tiers.
- Anything that reintroduces a per-direction idle has to solve that scale
  problem first. Per-pose `figure_h` is NOT the answer -- it trades a height
  wobble for a whole-body one, which is worse and harder to see in a test that
  measures figure height.
- The stand poses declare NO myth tier on purpose: there is no 8-bit standing
  pose in the design (8-bit idle is walk frame 0), so there is nothing honest
  to fall back to, and Assets raises loudly if the invariant is ever broken.
- `sprites/player/myth/2-bit-idle/` (the hand-generated greyscale 2-bit set)
  is now UNREFERENCED. It was three tonal levels of pure grey spread over 16
  noisy colours -- neither 2-bit nor tinted -- which is why the low tier is
  derived instead. Safe to delete.
- PUSHING is a NINE-frame stride per direction
  (`sprites/player/myth/push/<direction>/`), on a 48 canvas where the rest of
  the player art is 32 or 40 -- geometry is per descriptor and `figure_h`
  normalises the drawn size, so he still draws at 90px. It was two alternating
  poses before, which could not read as walking: his feet arrived and left
  without passing through anything.
- `PUSH_CYCLE_DISTANCE` is 117, derived not eyeballed: he pushes at
  `PLAYER_SPEED_X * PUSH_SPEED_FACTOR` (~2.2px/tick), so nine frames at the
  walk's ~5.9 ticks/frame needs ~117px of ground. It was 84, which across nine
  frames ran the cycle FASTER than his walk while he is meant to be straining.
  Lower it for a more hurried push, raise it for a heavier one.
- Pushing is no longer held back at 8-bit. It declares both tiers from the
  same nine frames (the rumour set derived by `tools/build_rumour.py`), because
  once everything else stepped down, reverting to full colour on touching a
  crate read as a rendering bug rather than as a tier.
- Referenced by NOTHING and safe to delete: `sprites/player/myth/pushing/`,
  the top-level `sprites/player/myth/<direction>.png` stills (the braced push
  frame 0), `sprites/player/myth/stand/` (true idle art, generated for the
  reverted directional-idle attempt), and `sprites/player/myth/2-bit-idle/`.
  `myth/stand/` is the one worth keeping around: it is the only real 8-bit
  standing art that exists, if a directional idle is ever attempted again.
- The switch from 2-bit to 8-bit is currently INSTANT. Making it gradual is the
  outstanding piece; `drawable[:alpha]` is forwarded by `Renderer.push_sprite`
  but set by nobody, so a crossfade has a hook waiting.
- The adversarial loop is GONE -- no enemy, no damage, no fail state, no
  pickup item. `creature.rb` replaces `enemy.rb`.
- Manipulation verbs are in: pushing (with weight, alignment, sliding and
  solid blocking) and throw-to-startle.
- The two-step pattern is in (`pattern.rb`): a socket starts hidden under an
  object that does not fit it; shifting that off reveals the mark, and pushing
  the matching object in reveals the region's seam. The ordering is enforced
  by objects blocking each other, not by a state machine.
- Story-doc question 4 is ANSWERED: a seam is an abstract object, not a door.
  Activating one opens no path -- it steps the bit style up (8-bit to 16-bit)
  for the character and the world around it. The fidelity system already
  delivers exactly that, so the effect is built, not placeholder. What is
  still a placeholder is the GESTURE: "walk into it" stands in until the real
  activation action is decided (one condition in `Seams.check_activated`).
- The bit-step is therefore ART-BLOCKED, not code-blocked. `Assets` declares
  no `:truth` tier for anything, so a resolved region logs a fallback and the
  player keeps his myth sprite. Ground colour is the only visible change
  today. Gray-box solids (creature, pushables, rock, seam) are NOT tier-aware
  at all -- `Renderer.push_solid` takes a fixed colour -- so they will only
  step up once they are real sprites going through `Assets`.
- The owl is in, as a real entity in world-space (`owl.rb`) that follows the
  player with slack rather than a fixed offset. It is airborne: its
  (x, depth) is the ground it is above, and `lift` raises only where it is
  drawn, so depth sorting is untouched.
- The owl has TWO EYES side by side, in every pose. This is not decoration:
  the doc calls the owl "the part of a person that already knows the truth,
  speaking from a vantage point the traveler hasn't reached yet", and the eyes
  make that literal. They are there from the FIRST FRAME and never change --
  per the doc the owl does not become more honest as bit-depth rises, only the
  player's capacity to understand it does. Do NOT gate them behind progression.
- Two eyes is the MAXIMUM the art can carry. Measured: the head is 22px wide
  in profile and one eye assembly (pale facial disc + amber iris + dark pupil)
  is 11px, so two fill it exactly. Three or four "eyes around the head" was
  tried and is geometrically impossible without a much larger head -- the
  generator shrinks them until they read as beading. The eyes-all-around idea
  survives in the PERCHED BACK VIEWS (`idle/north*.png`), which show amber eyes
  on the back of the skull.
- The owl art was REBUILT from a PixelLab character
  (`create_character` mode v3, 8 directions, seeded from a two-eye reference).
  Per-frame editing was tried first and failed: each frame reinterprets the
  head, so poses stopped matching each other. The v3 character pipeline is
  what produces one consistent bird -- and it is cheap (1 generation for all
  eight rotations).
- `animate_character` does NOT work for this owl. Asked for a wingbeat it
  produced a walk-like weight shift, and asked for a glide it produced an idle
  breathe -- it cannot invent flight from a perched pose. The wingbeat comes
  from `animate_image` seeded from an actual FLYING frame instead, which is the
  technique that works. Remember this before spending generations again.
- Poses: perched (`idle/`, all 8 directions, figure_h 40 foot_pad 4), soaring
  (`soaring/`, east+west, foot_pad 8) and a NINE-frame wingbeat
  (`wingbeat/<facing>/`, foot_pad 5 -- the MEDIAN of frames measuring 2 to 8,
  one value for all nine so the body's rise and fall through the stroke shows
  instead of being cancelled). Only east and west are wired, since the owl
  turns to look at the traveller; the other six perched directions are drawn
  and switching one on is a row in `Assets::OWL_POSES`, not new code.
- `flying/` and `flapping-wings/` (the old two-frame beat) are superseded and
  now referenced by nothing.
- The owl art is FLATTENED by `tools/simplify_owl.py`
  (`python3 tools/simplify_owl.py sprites/owl/myth`). Re-run it after
  regenerating any owl sprite; it rewrites in place and git history is the
  record of what the generator produced. PixelLab returns smooth, heavily
  shaded art -- 241 colours across the 34 frames -- where the traveller's own
  art is 24 colours and 39% flat black outline, so beside him the owl read as
  rendered rather than pixelled. The tool snaps every pixel to the 8 most-used
  colours, computed ACROSS ALL FRAMES so none invents its own shading.
- Palette selection is frequency order with a MINIMUM SEPARATION, not plain
  top-8. The art carries several near-identical blacks, each common enough to
  claim a slot; without the separation rule the palette came back as five
  blacks and the owl lost its entire light range. That bug reached disk once.
- The owl's EYES are a pale disc with a dark pupil and nothing between,
  matching how the traveller's eyes are drawn -- his carry no iris colour
  either. The amber iris drops out for free as a minority colour; the tool
  then binarises each eye, because the snap alone leaves mid-tones that read
  as a smudge. Eyes are found as small, high-up runs of the palest colour.
- The owl's amber eyes and its orange beak are THE SAME HUE, so no colour rule
  can keep one and drop the other. Losing both is deliberate and matches the
  traveller. Restoring the orange beak means hand-placing pixels.
- Frame count is free: `Assets.frame_path` buckets a normalised 0.0..1.0
  across however many files a descriptor lists, so callers never learn how
  many there are. `Assets::WINGBEAT_FRAMES` and `PUSH_FRAMES` are the only
  places those counts are written. `Assets.numbered_files` names a numbered
  cycle living in its own subfolder (the wingbeat and the push both do);
  `frame_paths` does the same for a cycle sitting directly in `dir`.
- The wingbeat is on a TIMER, unlike the player's distance-driven walk cycle,
  because a bird's beat rate has nothing to do with its ground speed.
  `OWL_FLAP_CYCLE_TICKS` (36) is ONE COMPLETE stroke -- it used to be
  `OWL_FLAP_TICKS` (8) meaning one half, doubled in owl.rb, which stopped
  meaning anything once the beat had no halves. 36 divides by 9, so each
  frame is held exactly four ticks. It is the one knob for how languid the
  owl looks.
- `foot_pad` is per pose because the canvases are registered differently;
  `figure_h` is shared, so the bird never changes size. The wingbeat declares
  6 (measured off the frames, not guessed): the generated cycle moves the
  whole BODY up and down, not just the wings, so one pad for all nine frames
  is what lets that bob show instead of cancelling it.
- Owl behaviour is a four-state machine: `:soaring` (the default -- glides
  high, slack-follows the player), `:descending`, `:perched`, `:climbing`.
  It lands only on pushables and the creature, NEVER the player, and it RIDES
  what it lands on. It beats its wings whenever it is actually going
  somewhere -- catching up, descending, climbing; the motionless glide is an
  occasional burst partway through a LONG crossing (`Owl.update_glide`, gated
  on `OWL_GLIDE_MIN_DISTANCE` and rolled once per completed stroke), plus
  holding station inside the slack radius. A perch ends on a randomised timer
  or when the player walks far enough away -- following stays dominant.
- `Assets` descriptors may now carry `height_px`, defaulting to
  `CHARACTER_HEIGHT_PX`. Not everything is person-sized; the owl would
  otherwise be drawn 90px tall.
- `OWL_HEIGHT_PX` is 40 because that is the ONE value that renders the owl
  1:1: Assets scales by `height_px / figure_h`, and every owl pose declares
  `figure_h` 40. It was 34 (a factor of 0.85), which made the owl the only
  asset in the game drawn SMALLER than authored -- detail was being discarded
  before it reached the screen. Retune it only alongside the poses' figure_h.
- GOTCHA: `height_px: Config::OWL_HEIGHT_PX` is captured when `assets.rb`
  loads, into `Assets::TABLE`. Hot-reloading `config.rb` alone therefore does
  NOT change the drawn size -- touch `assets.rb` (or restart) to see it. This
  bit once already; the constant looked applied while the owl still drew at
  the old scale.
- `Renderer.sprite_rect` is the one answer to "where was this drawn", used by
  the renderer and by the owl's click target and speech label so they cannot
  drift apart from the art.
- The owl speaks (`owl_speech.rb`) on exactly two things: the player CLICKING
  it, and the story having a hint to offer -- today only the doc's seam beat
  ("once a seam is revealed, the owl hints at how to activate it"). It does
  not chatter ambiently. Lines are keyed by stable id; text is PLACEHOLDER
  apart from the doc's draft line. `owl_speech.rb` reads other modules'
  public predicates and nothing reads it back -- deleting the file leaves the
  game running unchanged.
- Every line the owl speaks is logged to `args.state.owl_log` with the world
  state at that moment (regions resolved, seams revealed, patterns completed,
  where he stood, what tier he was drawn at). Context is recorded for a
  future WRITING pass and changes nothing about what is said -- per the doc,
  a repeated line stays verbatim and the reader changes around it. Toggle the
  per-firing print with `Config::OWL_LOG_FIRINGS`; `OwlSpeech.dump $args`
  prints the whole history from the console.
- Still to come: ambient life, world structure and traversal, the ending. Also unresolved: story-doc question 5, how many pattern moments the
  world holds and whether they share a rhythm.

## Git

Commit at each logical checkpoint (end of a step, not mid-feature) so there's
always a clean point to roll back to if a design change invalidates recent
work — which, on this project, happens more often than usual.
