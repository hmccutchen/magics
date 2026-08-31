
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
- `:rumour` has both a walk cycle and idle art. WALKING uses `player_walk` at
  its rumour tier (`2-bit-idle/2-bit-walking/frame_000..007`), the same eight
  frames/one-mirrored-side-view shape as the myth cycle, so cadence carries
  across the step-up and only fidelity changes. Its `figure_h` is 27, not the
  myth cycle's 26, because that is what the art measures -- declaring it
  truthfully is what makes both cycles draw the figure at the same 90px.
- STANDING STILL at `:rumour` uses `Assets::STAND_POSE_FILES`: eight held
  directional poses in `sprites/player/myth/2-bit-idle/`. These are the only
  real 8-direction art in the game, so the 2-bit traveller is the only one who
  genuinely faces north or south-west -- he turns to a true direction when he
  stops and returns to the mirrored side view when he walks. That angle swap
  on stopping is intended, and is the first thing to look at if he reads oddly.
  The stand poses declare NO myth tier on purpose: there is no 8-bit standing
  pose in the design (8-bit idle is walk frame 0), so there is nothing honest
  to fall back to, and Assets raises loudly if the invariant is ever broken.
- PUSHING is deliberately held back at 8-bit: the push poses declare no
  `:rumour` tier, so Assets falls back and logs it once. Drawing 2-bit push art
  and declaring it is the whole change when that art exists.
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
- The owl uses real sprite art (myth tier) in three poses -- perched, soaring,
  and a two-frame wingbeat -- east and west only, since it turns to look at
  the traveller. The other six directions are drawn and sitting in
  `sprites/owl/myth/`; switching one on is a row in `Assets::OWL_POSES`, not
  new code. `foot_pad` is per pose there because the canvases are registered
  differently; `figure_h` is shared, so the bird never changes size. The
  wingbeat is on a TIMER, unlike the player's distance-driven walk cycle,
  because a bird's beat rate has nothing to do with its ground speed.
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
  otherwise be drawn 90px tall. `Renderer.sprite_rect` is the one answer to
  "where was this drawn", used by the renderer and by the owl's click target
  and speech label so they cannot drift apart from the art.
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
