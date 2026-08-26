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

  # A textured sprite. Same shape as `solid` -- which is itself a sprite with
  # the built-in :solid path -- so both go into the same ordered collection and
  # sort against each other by depth.
  #
  # `flip_horizontally` is how DragonRuby mirrors a sprite, which is what lets
  # one right-facing art set serve both directions.
  def self.image x, y, w, h, path, flip = false, alpha = 255
    {
      x: x, y: y, w: w, h: h,
      path: path,
      flip_horizontally: flip,
      a: alpha
    }
  end

  # Expand a [r, g, b] array into the keys DragonRuby's render hashes want.
  def self.rgb color
    { r: color[0], g: color[1], b: color[2] }
  end
end
