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

  # Alpha used on the blink-off phase of the post-hit recovery window. The
  # gray-box used a flat colour swap; a sprite blinks by fading instead.
  RECOVERY_BLINK_ALPHA = 90

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
  PLAYER_SPEED_X     = 4.0
  PLAYER_SPEED_DEPTH = 2.6

  # Multiplier applied to both axes when moving diagonally, so that walking
  # diagonally is not faster than walking straight. (1 / sqrt(2))
  DIAGONAL_FACTOR = 0.7071

  # --- Pickup item ----------------------------------------------------------
  #
  # The thing you walk into to reveal the seam. Placed toward the front-left of
  # the stage so that reaching it requires moving on both axes.
  ITEM_X     = 300
  ITEM_DEPTH = 60.0
  ITEM_W     = 30
  ITEM_H     = 30
  ITEM_FW    = 34
  ITEM_FD    = 26

  # --- Seam (goal) ----------------------------------------------------------
  #
  # Hidden until the item is carried. Placed at the back-right, diagonally
  # opposite the item, so the two objectives are not on the same walk.
  SEAM_X     = 1000
  SEAM_DEPTH = 250.0
  SEAM_W     = 26
  SEAM_H     = 120
  SEAM_FW    = 46
  SEAM_FD    = 30

  # --- Enemy ----------------------------------------------------------------

  ENEMY_W  = 44
  ENEMY_H  = 80
  ENEMY_FW = 40
  ENEMY_FD = 26

  # Slower than the player on both axes, so it can be outwalked but not ignored.
  ENEMY_SPEED = 2.0

  # The patrol circuit, as [x, depth] pairs walked in order and then repeated.
  # Note it crosses the full depth range: the enemy passes both in front of and
  # behind the player, which is what makes the draw-order sorting visible.
  ENEMY_PATROL_POINTS = [
    [850,  40],   # front-right
    [850, 260],   # back-right
    [450, 260],   # back-left
    [450,  40]    # front-left
  ]

  # How close (in mixed x/depth units) counts as reaching a waypoint. Must be
  # larger than ENEMY_SPEED or the enemy oversteps and orbits the point forever.
  ENEMY_ARRIVE_DISTANCE = 4.0

  # --- Throw / rock ---------------------------------------------------------
  #
  # The player's only "action". It never harms the enemy -- it just makes a
  # noise somewhere else, which the enemy walks over to investigate.
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

  # Frames the enemy spends standing at the landing spot before resuming.
  ENEMY_INVESTIGATE_TICKS = 90

  # --- Recovery -------------------------------------------------------------
  #
  # Frames of immunity after the enemy catches you. 60 ticks == 1 second, since
  # DragonRuby is a fixed 60fps. Without this, standing inside the enemy would
  # strip the item again the instant you re-collected it.
  RECOVERY_TICKS = 60

  # How fast the player blinks while recovering (frames per on/off phase).
  RECOVERY_BLINK_RATE = 6

  # --- Completion -----------------------------------------------------------

  BANNER_H          = 150
  BANNER_ALPHA      = 225
  BANNER_TITLE_PX   = 52
  BANNER_PROMPT_PX  = 22

  # --- Gray-box palette -----------------------------------------------------
  # Plain [r, g, b] arrays. Splatted into render hashes by Renderer.

  COLOR_BACKGROUND = [24, 26, 32]
  COLOR_SKY        = [38, 42, 54]
  COLOR_GROUND     = [52, 56, 68]
  COLOR_GROUND_MYTH  = [52, 56, 68]
  COLOR_GROUND_TRUTH = [86, 96, 82]
  COLOR_GRID       = [70, 76, 92]
  COLOR_HORIZON    = [92, 100, 120]
  COLOR_PLAYER     = [214, 122, 92]
  COLOR_ITEM       = [226, 196, 92]
  COLOR_SEAM       = [138, 210, 196]
  COLOR_ENEMY      = [176, 92, 162]
  COLOR_PLAYER_HIT = [120, 124, 140]
  COLOR_ROCK       = [206, 206, 214]
  COLOR_BANNER_BG  = [16, 18, 24]
  COLOR_BANNER     = [138, 210, 196]
  COLOR_TEXT_DIM   = [130, 136, 150]
end
