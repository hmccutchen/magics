# Scene
#
# The static backdrop: sky, ground plane, horizon, and depth reference lines.
# Nothing here moves or has state.
#
# EVERYTHING in this game draws into args.outputs.sprites -- backdrop and
# entities alike. Output collections are LAYERED relative to each other (every
# line draws above every sprite, regardless of push order), so splitting the
# scene across `sprites` and `lines` painted the depth grid on top of the
# player. One collection, insertion-ordered, is the only way to control the
# stack. Scene renders before Renderer, so the backdrop stays behind.
module Scene
  # How many reference lines to rule across the ground plane. Purely a gray-box
  # readability aid so you can see the depth axis; art will replace this.
  DEPTH_LINE_COUNT = 6

  GRID_LINE_THICKNESS    = 1
  HORIZON_LINE_THICKNESS = 2

  def self.render args
    args.outputs.background_color = Config::COLOR_BACKGROUND

    sky args
    ground args
    depth_lines args
    horizon args
  end

  def self.sky args
    args.outputs.sprites << solid(
      0,
      Config::GROUND_Y_FAR,
      Config::SCREEN_W,
      Config::SCREEN_H - Config::GROUND_Y_FAR,
      Config::COLOR_SKY
    )
  end

  def self.ground args
    args.outputs.sprites << solid(
      0,
      Config::GROUND_Y_NEAR,
      Config::SCREEN_W,
      Config::GROUND_Y_FAR - Config::GROUND_Y_NEAR,
      Config::COLOR_GROUND
    )
  end

  # One horizontal rule per evenly spaced depth. Spacing is even in DEPTH, and
  # since our depth->y mapping is linear it comes out even on screen too. If we
  # ever switch to a perspective mapping these will bunch toward the horizon on
  # their own, which is a useful visual check that the mapping is working.
  def self.depth_lines args
    DEPTH_LINE_COUNT.times do |i|
      t     = i / (DEPTH_LINE_COUNT - 1).to_f
      depth = Config::DEPTH_NEAR + t * (Config::DEPTH_FAR - Config::DEPTH_NEAR)

      args.outputs.sprites << solid(
        0,
        World.ground_y(depth),
        Config::SCREEN_W,
        GRID_LINE_THICKNESS,
        Config::COLOR_GRID
      )
    end
  end

  def self.horizon args
    args.outputs.sprites << solid(
      0,
      Config::GROUND_Y_FAR,
      Config::SCREEN_W,
      HORIZON_LINE_THICKNESS,
      Config::COLOR_HORIZON
    )
  end

  # The one filled-rectangle constructor for the whole project.
  #
  # Two DragonRuby constraints are baked into this signature:
  #
  #   1. Arguments are POSITIONAL, not keyword. DragonRuby's mruby silently
  #      returns nil from any method declared with required keyword arguments
  #      (`def self.solid x:, y:`) -- no exception, no warning, the method just
  #      evaluates to nothing. Keyword args WITH defaults do work, but
  #      positional is the safer habit here.
  #
  #   2. DragonRuby 7.15 deprecated the `solid` primitive. The replacement is a
  #      sprite whose path is the built-in :solid texture -- same result,
  #      several times faster, and no deprecation notification on screen.
  # `alpha` defaults to fully opaque; the completion banner uses it to dim the
  # scene behind the text without hiding it.
  def self.solid x, y, w, h, color, alpha = 255
    { x: x, y: y, w: w, h: h, path: :solid, a: alpha, **rgb(color) }
  end

  # Expand a [r, g, b] array into the keys DragonRuby's render hashes want.
  def self.rgb color
    { r: color[0], g: color[1], b: color[2] }
  end
end
