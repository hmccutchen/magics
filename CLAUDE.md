
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
- No jumping, no gravity -- this is a walking-based game.
- Collision uses ground-plane footprint checks in world (x, depth) space,
  not screen-space.
- Bit-depth fidelity system is in: regions are myth or truth, and a region's
  tier resolves what its contents are drawn as (`regions.rb`, `assets.rb`).
- The adversarial loop is GONE -- no enemy, no damage, no fail state, no
  pickup item. `creature.rb` replaces `enemy.rb`.
- Manipulation verbs are in: pushing (with weight, alignment, sliding and
  solid blocking) and throw-to-startle.
- The two-step pattern is in (`pattern.rb`): a socket starts hidden under an
  object that does not fit it; shifting that off reveals the mark, and pushing
  the matching object in reveals the region's seam. The ordering is enforced
  by objects blocking each other, not by a state machine.
- Walking into a revealed seam is still a PLACEHOLDER for activation --
  story-doc open question 4 (what activating a seam changes on screen) is
  unresolved, so only the rendering half of it exists: the region flips to
  truth and its ground and contents change tier.
- The owl is in, as a real entity in world-space (`owl.rb`) that follows the
  player with slack rather than a fixed offset. It is airborne: its
  (x, depth) is the ground it is above, and `lift` raises only where it is
  drawn, so depth sorting is untouched.
- The owl speaks (`owl_speech.rb`) on exactly two things: the player CLICKING
  it, and the story having a hint to offer -- today only the doc's seam beat
  ("once a seam is revealed, the owl hints at how to activate it"). It does
  not chatter ambiently. Lines are keyed by stable id; text is PLACEHOLDER
  apart from the doc's draft line. `owl_speech.rb` reads other modules'
  public predicates and nothing reads it back -- deleting the file leaves the
  game running unchanged.
- Still to come: ambient life, world structure and traversal, the ending. Also unresolved: story-doc question 5, how many pattern moments the
  world holds and whether they share a rhythm.

## Git

Commit at each logical checkpoint (end of a step, not mid-feature) so there's
always a clean point to roll back to if a design change invalidates recent
work — which, on this project, happens more often than usual.
