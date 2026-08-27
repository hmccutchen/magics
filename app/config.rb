# Config
#
# Constants that describe the shape of the world. Kept in one place so that
# tuning the feel of the game is a matter of editing numbers here rather than
# hunting for magic values scattered through the update and render code.
module Config
  # DragonRuby's logical resolution is always this, regardless of window size.
  SCREEN_W = 1280
  SCREEN_H = 720

  # --- The depth axis -------------------------------------------------------
  #
  # `depth` is a pure game-logic number in arbitrary world units. It is NOT a
  # screen coordinate. DEPTH_NEAR is the front of the stage (closest to the
  # camera); DEPTH_FAR is the back. Nothing outside World knows how depth
  # relates to the screen.
  DEPTH_NEAR = 0.0
  DEPTH_FAR  = 300.0

  # The band of screen y that the walkable ground plane occupies. Because
  # DragonRuby's y axis points up, receding into the scene means moving UP the
  # screen, so GROUND_Y_FAR is the larger number. This pair of constants is the
  # only place the depth axis touches screen space.
  GROUND_Y_NEAR = 90
  GROUND_Y_FAR  = 400

  # How much an entity shrinks as it recedes. Linear across the depth range.
  SCALE_NEAR = 1.0
  SCALE_FAR  = 0.55

  # --- Player ---------------------------------------------------------------

  # On-screen height of the character FIGURE at full scale, in pixels. Each
  # tier's drawn canvas size is derived from this and that tier's own
  # measurements, so the traveller stays the same apparent size no matter which
  # tier he is rendered at. Without this he would visibly resize when crossing
  # a region boundary, which reads as a bug rather than a revelation.
  #
  # Per-sprite measurements (canvas size, figure height, foot padding, frame
  # count) live in app/assets.rb beside the files they describe. They were never
  # tuning constants; this file keeps only what is tuned by feel.
  CHARACTER_HEIGHT_PX = 90

  # Draws region outlines and names over the scene. Authoring tool, not a HUD:
  # region bounds are written in (x, depth) units that correspond to nothing
  # visible on screen, and unlike a numeric readout this shows SPATIAL
  # information that cannot be read any other way. Delete once regions are
  # placed.
  SHOW_REGIONS = false

  # Ground covered by ONE FULL walk cycle. Previously this was distance per
  # frame, which broke as soon as tiers could have different frame counts: a
  # 4-frame cycle would have completed in half the distance and animated at a
  # visibly different speed. Expressing the whole cycle makes cadence identical
  # across tiers by construction.
  WALK_CYCLE_DISTANCE = 160.0

  # Footprint: the entity's box on the GROUND PLANE, used for collision.
  # FW is horizontal in pixels; FD is depth in world units. This is deliberately
  # not the same as the drawn rectangle -- collision happens in game space, and
  # a footprint shallower than the body reads better because it means you have
  # to genuinely stand on a thing rather than merely lean over it.
  PLAYER_FW = 34
  PLAYER_FD = 22

  # Pixels per frame. There is no delta time, so these are literally the amount
  # added each tick. Depth is slower than x on purpose: the depth axis is
  # visually compressed, so matching speeds makes depth movement feel too fast.
  #
  # The ratio between them is held at roughly 0.65 when retuning, so that
  # changing the walking pace does not also change the shape of the stage.
  #
  # Nothing else needs adjusting alongside these: the walk cycle and the push
  # bob are both driven by ground covered rather than by a timer, so cadence
  # follows the new speed on its own.
  PLAYER_SPEED_X     = 3.4
  PLAYER_SPEED_DEPTH = 2.2

  # Multiplier applied to both axes when moving diagonally, so that walking
  # diagonally is not faster than walking straight. (1 / sqrt(2))
  DIAGONAL_FACTOR = 0.7071

  # --- Creature -------------------------------------------------------------
  #
  # An animal, not an adversary. These are the numbers that describe where it
  # goes and how fast; nothing here can hurt the player.

  CREATURE_W  = 44
  CREATURE_H  = 80
  CREATURE_FW = 40
  CREATURE_FD = 26

  # Slower than the player on both axes, so the player can always walk around
  # it rather than being held up by it.
  CREATURE_SPEED = 2.0

  # A startled animal bolts. Faster than the player, but only for the few
  # strides it takes to clear FLEE_DISTANCE -- long enough to read as alarm,
  # too short to be a chase.
  CREATURE_FLEE_SPEED = 3.8

  # The circuit of grazing spots, as [x, depth] pairs walked in order and then
  # repeated. Note it crosses the full depth range: the creature passes both in
  # front of and behind the player, which is what makes the draw-order sorting
  # visible.
  #
  # Inherited from the retired patrol and still shaped like one -- a constant
  # circuit of the whole stage reads as marching, not grazing. Retuning this
  # into something that stays near one clearing belongs with the throw work,
  # where how the creature moves is the actual subject.
  CREATURE_GRAZING_POINTS = [
    [850,  40],   # front-right
    [850, 260],   # back-right
    [450, 260],   # back-left
    [450,  40]    # front-left
  ]

  # How close (in mixed x/depth units) counts as reaching a spot. Must be
  # larger than the fastest creature speed or it oversteps every frame and
  # orbits the point forever. Creature asserts this on load.
  CREATURE_ARRIVE_DISTANCE = 5.0

  # --- Making it move like an animal ---------------------------------------
  #
  # Left alone the creature walked its circuit at exactly one speed, turned
  # instantly and never stopped, which reads as a patrol rather than an animal.
  # These fix that between them: it stops to graze, and it eases in and out of
  # walking instead of snapping to full pace.

  # Frames spent standing at a spot before moving on. A range rather than one
  # value, so the circuit does not fall into an audible rhythm.
  CREATURE_GRAZE_TICKS_MIN = 90
  CREATURE_GRAZE_TICKS_MAX = 260

  # Added to its speed each frame while getting under way. At 0.06 an amble
  # takes about half a second to reach full pace.
  CREATURE_ACCELERATION = 0.06

  # Distance from its target at which it starts easing off, so it arrives
  # rather than stopping dead on the spot.
  CREATURE_SLOWDOWN_DISTANCE = 45.0

  # Floor on the eased speed. Without it the deceleration curve approaches zero
  # and the creature creeps toward its target without ever arriving. Must stay
  # below CREATURE_ARRIVE_DISTANCE; Creature asserts this on load.
  CREATURE_MIN_SPEED = 0.45

  # How near a thrown object has to land before the creature notices it.
  # Beyond this it carries on grazing, which is what keeps the throw a tool for
  # moving an animal off a specific spot rather than a remote control.
  CREATURE_STARTLE_RADIUS = 130.0

  # How far it bolts once startled. Roughly its own body length several times
  # over -- far enough to clear whatever it was standing on.
  CREATURE_FLEE_DISTANCE = 95.0

  # Frames the creature spends standing still after bolting, before it settles
  # and drifts back to grazing. Lives here rather than with the throw
  # constants: it describes the creature's behaviour, not the object's flight.
  CREATURE_SETTLE_TICKS = 90

  # --- Pushing --------------------------------------------------------------
  #
  # Multiplies the player's speed while pushing, so shifting something has
  # weight to it. Applied to both axes and on top of DIAGONAL_FACTOR. The
  # object copies the player's slowed delta, so it slows down too.
  PUSH_SPEED_FACTOR = 0.65

  # How far INSIDE a pushable's footprint the player has to reach before it
  # will shift, measured ACROSS the direction of travel. Brushing past the
  # front or back of a thing should not move it; you have to square up first.
  #
  # Separate per axis because they are different units -- x is pixels, depth is
  # world units -- the same reason THROW_DISTANCE is split in two.
  #
  # INSET_DEPTH applies when walking left or right, and is the one that matters:
  # it is what decides whether you shove an object or simply pass in front of
  # it. Raise it to demand tighter lining-up.
  #
  # INSET_X applies when walking into or out of the scene, and is deliberately
  # zero. Coming at something head-on, any horizontal contact should shift it;
  # requiring you to be centred as well felt arbitrary, because there is no
  # equivalent of "passing in front of it" along that axis.
  PUSH_CONTACT_INSET_X     = 0
  PUSH_CONTACT_INSET_DEPTH = 10

  # --- How a pushed object LOOKS moving ------------------------------------
  #
  # Presentation only. A pushed object's real position stays locked to the
  # player -- that is what makes collision correct without any resolution
  # step -- but it is DRAWN trailing slightly behind and catching up, so it
  # gives a little under the hand instead of sliding like a decal.
  #
  # Nothing in the simulation reads these. Collision, blocking and the seam
  # all use the true position.
  #
  # Fraction of the lag remaining after each frame. Lower snaps tighter,
  # higher drags more. At 0.75 a steady push settles about 6-7px behind.
  PUSH_LAG_DECAY = 0.75

  # Ceiling on the trail, so a restart or a hot-reload jump cannot fling the
  # drawn box across the stage.
  PUSH_LAG_MAX = 12.0

  # The push pose is a single held frame, so without this he slides across the
  # ground with no sign of effort. A small rise and fall gives the movement a
  # footfall to read against.
  #
  # Peak height in screen pixels at full scale. Stopgap until push-walk art
  # exists, at which point this and Player.push_bob both go.
  PUSH_BOB_PX = 3

  # Footfalls per full walk cycle. Two, because a cycle is a left and a right
  # step -- keeping it expressed in steps rather than as a raw frequency means
  # it stays correct if WALK_CYCLE_DISTANCE is retuned.
  PUSH_BOB_STEPS = 2

  # --- Throw / rock ---------------------------------------------------------
  #
  # The player's only "action". It never harms the creature -- it just makes a
  # noise somewhere else, which the creature reacts to.
  ROCK_W  = 14
  ROCK_H  = 14
  ROCK_FW = 20
  ROCK_FD = 18

  # Holding the throw key winds it up. Frames to reach a full-strength throw;
  # releasing earlier throws proportionally shorter. Short enough to stay
  # tactile rather than becoming a meter to manage.
  THROW_CHARGE_TICKS = 36

  # How far the rock travels from the player, per axis, at a tap and at a full
  # wind-up. Separate per axis because x is pixels and depth is world units.
  #
  # The minimum is deliberately well short of CREATURE_STARTLE_RADIUS, so a
  # tap can be dropped near your own feet without startling anything, and the
  # maximum comfortably past it.
  THROW_DISTANCE_X_MIN     = 110
  THROW_DISTANCE_X_MAX     = 340
  THROW_DISTANCE_DEPTH_MIN = 38
  THROW_DISTANCE_DEPTH_MAX = 115

  # Frames in the air, scaled with the throw's strength. A short toss that hung
  # in the air as long as a full one reads as floating.
  THROW_FLIGHT_TICKS_MIN = 15
  THROW_FLIGHT_TICKS_MAX = 30

  # Peak height of the rock's visual arc, in screen pixels, also scaled with
  # strength. Purely cosmetic -- the rock's depth, and therefore its draw
  # order, follows the ground path regardless.
  ROCK_ARC_HEIGHT_MIN = 40
  ROCK_ARC_HEIGHT_MAX = 100

  # Frames the landed rock stays visible before disappearing.
  ROCK_LINGER_TICKS = 36

  # --- The pattern ----------------------------------------------------------
  #
  # How close an object has to be to count as seated in a socket. Split per
  # axis because x is pixels and depth is world units -- a single distance
  # across the two would be tighter on one axis than the other without ever
  # saying so.
  #
  # These also set the drawn size of the socket, so the mark on the ground is
  # exactly the area that counts. There is no hidden margin: what you see is
  # what has to be filled.
  SOCKET_TOLERANCE_X     = 26
  SOCKET_TOLERANCE_DEPTH = 18.0

  # --- Gray-box palette -----------------------------------------------------
  # Plain [r, g, b] arrays. Splatted into render hashes by Renderer.

  COLOR_BACKGROUND = [24, 26, 32]
  COLOR_SKY        = [38, 42, 54]
  COLOR_GROUND_MYTH  = [52, 56, 68]
  COLOR_GROUND_TRUTH = [86, 96, 82]
  COLOR_GRID       = [70, 76, 92]
  COLOR_HORIZON    = [92, 100, 120]
  COLOR_SEAM       = [138, 210, 196]
  COLOR_CREATURE   = [176, 92, 162]
  COLOR_ROCK       = [206, 206, 214]

  # One per Throwables::KINDS entry, in the same order. Colour is how the two
  # are told apart until there is art for them.
  COLOR_THROWABLE = [
    [232, 206, 118],   # lure  -- warm, draws things in
    [104, 176, 214]    # scare -- cold, drives things off
  ]
  # One per Pushable::PUSHABLES entry, in the same order. The second echoes
  # COLOR_SOCKET, because the pattern the player has to notice is that the two
  # belong together -- with real art that kinship is the art's job.
  COLOR_PUSHABLE = [
    [150, 138, 108],
    [116, 150, 138]
  ]

  COLOR_SOCKET        = [104, 134, 124]
  COLOR_SOCKET_FILLED = [138, 210, 196]
  COLOR_REGION_RESOLVED = [138, 210, 196]
end
