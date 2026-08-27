# Owl
#
# A companion that moves through the same world-space as everything else, per
# the existing (x, depth) convention -- not a UI overlay and not a dialogue
# box. That choice is what lets it go through Assets/Regions like every other
# entity once it has art: Renderer resolves fidelity from an entity's ground
# position, so an owl WITHOUT one could never be told what tier to draw at.
#
# It does not stand on the floor. Its (x, depth) is the spot on the ground it
# is ABOVE, and `lift` raises the drawn sprite off that spot -- the same
# mechanism the thrown rock uses to look airborne while still sorting by where
# it is on the ground. Depth sorting therefore keeps working unchanged: an owl
# high in the air still passes behind whatever is nearer the camera than the
# ground beneath it.
#
# It follows with SLACK rather than a fixed offset. The player has to walk far
# enough to open a gap before the owl bothers to move, so it is usually ahead
# of him or catching up, rarely exactly beside him. That reads as something
# keeping its own company rather than a cursor stuck to his shoulder.
#
# Modes:
#   :perched  sitting still, low, letting the gap open
#   :flying   closing the gap to its anchor, higher off the ground
#
# No lines yet. Speech is the next slice; this file is only the body.
module Owl
  def self.defaults args
    args.state.owl ||= args.state.new_entity(:owl) do |owl|
      player = args.state.player

      # Spawns already on its anchor so the first frame is not a swoop across
      # the stage from wherever the default happened to put it.
      owl.x, owl.depth = anchor_for player

      owl.w  = Config::OWL_W
      owl.h  = Config::OWL_H
      owl.fw = Config::OWL_FW
      owl.fd = Config::OWL_FD

      owl.mode  = :perched
      owl.speed = 0.0

      # Current drawn height, eased toward whichever height the mode wants.
      # Stored rather than derived so the rise and drop carry across frames
      # instead of snapping the instant the mode flips.
      owl.lift = Config::OWL_PERCH_LIFT
    end
  end

  # Runs after Player, so it chases where the player IS this frame rather than
  # trailing a frame behind him.
  def self.update args
    defaults args

    owl    = args.state.owl
    anchor = anchor_for args.state.player

    case owl.mode
    when :perched then consider_taking_off owl, anchor
    when :flying  then fly owl, anchor
    end

    ease_lift owl
  end

  # Where the owl wants to be: behind the player along x and a little further
  # into the scene. Mirrored by heading_x -- NOT facing_x, which legitimately
  # goes to zero when walking straight along the depth axis and would park the
  # owl on top of him -- so it swaps to his other side when he turns around.
  def self.anchor_for player
    depth = World.clamp_depth player.depth + Config::OWL_FOLLOW_OFFSET_DEPTH
    x     = World.clamp_x(
      player.x - (player.heading_x * Config::OWL_FOLLOW_OFFSET_X),
      Config::OWL_FW,
      depth
    )

    [x, depth]
  end

  # Sits still until the gap is worth crossing. The slack radius is the entire
  # difference between a companion and a fixed offset.
  def self.consider_taking_off owl, anchor
    return if distance_to(owl, anchor) <= Config::OWL_SLACK_RADIUS

    owl.mode = :flying
  end

  def self.fly owl, anchor
    distance = distance_to owl, anchor

    if distance <= Config::OWL_ARRIVE_DISTANCE
      owl.speed = 0.0
      owl.mode  = :perched
      return
    end

    owl.speed = eased_speed owl, distance

    # Nothing blocks the owl: it is in the air, so pushables and the creature
    # are beneath it. This is deliberately NOT the creature's move_toward --
    # that one collision-checks against the ground plane, which would stop a
    # flying bird dead on a crate.
    owl.x     += ((anchor[0] - owl.x) / distance) * owl.speed
    owl.depth  = World.clamp_depth(
      owl.depth + (((anchor[1] - owl.depth) / distance) * owl.speed)
    )
  end

  # Ramp up from rest, ease down over the last stretch so it settles onto the
  # perch instead of stopping dead. Floored so the curve cannot approach zero
  # and leave it drifting in forever.
  def self.eased_speed owl, distance
    ceiling = Config::OWL_SPEED
    ceiling = Config::OWL_SPEED * (distance / Config::OWL_SLOWDOWN_DISTANCE) if distance < Config::OWL_SLOWDOWN_DISTANCE
    ceiling = Config::OWL_MIN_SPEED if ceiling < Config::OWL_MIN_SPEED

    stepped = owl.speed + Config::OWL_ACCELERATION

    stepped > ceiling ? ceiling : stepped
  end

  # Moves a fixed fraction of the remaining gap each frame, so it rises fast
  # off the perch and arrives gently -- and never overshoots, whatever the two
  # heights are retuned to.
  def self.ease_lift owl
    target = owl.mode == :flying ? Config::OWL_FLIGHT_LIFT : Config::OWL_PERCH_LIFT

    owl.lift += (target - owl.lift) * Config::OWL_LIFT_EASE
  end

  # Mixed units, the same caveat the creature's circuit carries: x is pixels
  # and depth is world units, so this magnitude is not one consistent
  # real-world quantity. It is driving how a bird decides to move, not
  # physics, so eyeballed is fine.
  def self.distance_to owl, anchor
    dx = anchor[0] - owl.x
    dd = anchor[1] - owl.depth

    Math.sqrt((dx * dx) + (dd * dd))
  end

  # An arrive distance at or below the step size means the owl oversteps its
  # anchor every frame and circles it forever, which reads as a bug in the
  # following rather than a mistuned constant. Refuse to start instead -- the
  # same stance Creature takes on its own speeds. Runs on load, and therefore
  # again on every hot-reload of this file.
  def self.assert_arrive_distance_exceeds_speed!
    return if Config::OWL_ARRIVE_DISTANCE > Config::OWL_SPEED

    raise "OWL_ARRIVE_DISTANCE (#{Config::OWL_ARRIVE_DISTANCE}) must exceed OWL_SPEED (#{Config::OWL_SPEED})"
  end

  # A floor above the arrive distance steps past the anchor every frame, which
  # is the same orbiting bug from the other direction.
  def self.assert_min_speed_arrives!
    return if Config::OWL_MIN_SPEED < Config::OWL_ARRIVE_DISTANCE

    raise "OWL_MIN_SPEED (#{Config::OWL_MIN_SPEED}) must stay below OWL_ARRIVE_DISTANCE (#{Config::OWL_ARRIVE_DISTANCE})"
  end

  # Taking off only to arrive instantly would make the owl twitch between
  # modes on the spot instead of flying anywhere.
  def self.assert_slack_exceeds_arrive_distance!
    return if Config::OWL_SLACK_RADIUS > Config::OWL_ARRIVE_DISTANCE

    raise "OWL_SLACK_RADIUS (#{Config::OWL_SLACK_RADIUS}) must exceed OWL_ARRIVE_DISTANCE (#{Config::OWL_ARRIVE_DISTANCE})"
  end

  assert_arrive_distance_exceeds_speed!
  assert_min_speed_arrives!
  assert_slack_exceeds_arrive_distance!
end
