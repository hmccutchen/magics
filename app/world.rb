# World
#
# The single conversion layer between game-logic space and screen space.
#
# Game logic thinks in (x, depth). Rendering needs (screen x, screen y, scale).
# Every translation between the two happens here, so if we later change the
# ground band, the scale falloff, or add horizontal foreshortening, this is the
# only file that changes.
#
# Convention: an entity's (x, depth) is its GROUND CONTACT POINT -- the spot
# where its feet meet the floor, horizontally centered. It is not the corner of
# a rectangle. That is what makes scaling look right: a shrinking entity stays
# planted on the ground instead of drifting off it.
module World
  # Normalize a depth to 0.0 (nearest) .. 1.0 (farthest).
  # Everything else in this module is expressed in terms of this.
  def self.depth_t depth
    (depth - Config::DEPTH_NEAR) / (Config::DEPTH_FAR - Config::DEPTH_NEAR)
  end

  # Keep a depth inside the walkable band.
  def self.clamp_depth depth
    depth.clamp Config::DEPTH_NEAR, Config::DEPTH_FAR
  end

  # Screen y of the ground at this depth. Larger depth => larger y, because
  # DragonRuby's y axis points up and the scene recedes upward.
  def self.ground_y depth
    t = depth_t depth
    Config::GROUND_Y_NEAR + t * (Config::GROUND_Y_FAR - Config::GROUND_Y_NEAR)
  end

  # Draw scale at this depth. Linear from SCALE_NEAR to SCALE_FAR.
  def self.scale depth
    t = depth_t depth
    Config::SCALE_NEAR + t * (Config::SCALE_FAR - Config::SCALE_NEAR)
  end

  # Turn a logical entity into the rectangle DragonRuby wants to draw.
  #
  # `entity` is any object responding to x, depth, w, h -- w and h being the
  # size at SCALE_NEAR. Returns the bottom-left-anchored rect that DragonRuby's
  # render hashes expect, with the entity's feet planted at ground_y.
  # `lift` raises the drawn rect above the ground plane without changing the
  # entity's depth. Used for the thrown rock's arc: it must LOOK airborne while
  # still sorting by where it is on the ground.
  def self.screen_rect entity, lift = 0
    place entity.x, entity.depth, entity.w, entity.h, lift
  end

  # Converts a ground position and an UNSCALED size into the screen rectangle
  # DragonRuby draws. Split out from screen_rect because a sprite's drawn size
  # comes from its tier descriptor rather than from the entity, so the caller
  # supplies w and h directly.
  def self.place x, depth, w, h, lift = 0
    s = scale depth

    drawn_w = w * s
    drawn_h = h * s

    {
      x: x - (drawn_w / 2.0),   # x is the entity's center, so back off half
      y: ground_y(depth) + lift, # y is the entity's feet, and DR rects anchor
      w: drawn_w,                # at bottom-left, so this needs no adjustment
      h: drawn_h
    }
  end

  # --- Collision ------------------------------------------------------------
  #
  # Collision happens on the GROUND PLANE, in (x, depth) space -- never against
  # the drawn rectangles. This is the one thing a depth game has to get right:
  # two entities at different depths can overlap heavily on screen while being
  # most of the stage apart in the world, so screen-space intersection would
  # report constant false collisions.
  #
  # The footprint is a top-down box. We map it into a rect so we can reuse
  # DragonRuby's Geometry mixin, which means `y` here holds DEPTH, not a screen
  # coordinate. That reuse is worth the small mental hiccup; the rect never
  # escapes this module.
  def self.footprint entity
    footprint_at entity.x, entity.depth, entity.fw, entity.fd
  end

  # The same box, for a position an entity has not moved to yet. Collision
  # response has to ask "would this land me inside something" BEFORE committing
  # the move, which an entity-shaped argument cannot express.
  def self.footprint_at x, depth, fw, fd
    {
      x: x - (fw / 2.0),
      y: depth - (fd / 2.0),
      w: fw,
      h: fd
    }
  end

  # Do two entities overlap on the ground plane?
  # intersect_rect? is mixed into Hash by DragonRuby's Geometry module. It has a
  # default tolerance of 0.1, so merely touching edges does not count.
  def self.overlap? a, b
    footprint(a).intersect_rect? footprint(b)
  end

  # Would a box of this size, placed here, overlap `other`?
  def self.would_overlap? x, depth, fw, fd, other
    footprint_at(x, depth, fw, fd).intersect_rect? footprint(other)
  end

  # Horizontal bounds for an entity at a given depth, so it cannot walk far
  # enough off-screen to vanish. Accounts for the entity's scaled width.
  def self.clamp_x x, entity_w, depth
    half = (entity_w * scale(depth)) / 2.0
    x.clamp half, Config::SCREEN_W - half
  end
end
