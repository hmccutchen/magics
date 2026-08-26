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
  SHOW_REGIONS = true

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
  # larger than CREATURE_SPEED or the creature oversteps and orbits forever.
  CREATURE_ARRIVE_DISTANCE = 4.0

  # Frames the creature spends standing at a landing spot before resuming its
  # circuit. Lives here rather than with the throw constants: it describes the
  # creature's behaviour, not the object's flight.
  CREATURE_LINGER_TICKS = 90

  # --- Pushing --------------------------------------------------------------
  #
  # A pushable is displaced by the player's own movement for the frame, scaled
  # by this. 1.0 means it travels exactly as fast as you walk, which is the
  # only value at which it can neither outrun you nor be walked through.
  # Lower values read as "heavy" but let the player overlap the object, since
  # nothing blocks the player yet.
  PUSH_FACTOR = 1.0

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

  # How far the rock travels from the player, per axis, at full facing.
  # Separate constants because x is pixels and depth is world units.
  THROW_DISTANCE_X     = 280
  THROW_DISTANCE_DEPTH = 95

  # Frames the rock spends in the air. At 60fps this is ~0.4s.
  THROW_FLIGHT_TICKS = 24

  # Peak height of the rock's visual arc, in screen pixels. Purely cosmetic --
  # the rock's depth (and therefore its draw order) follows the ground path.
  ROCK_ARC_HEIGHT = 90

  # Frames the landed rock stays visible before disappearing.
  ROCK_LINGER_TICKS = 36

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
  COLOR_PUSHABLE   = [150, 138, 108]
  COLOR_REGION_RESOLVED = [138, 210, 196]
end
