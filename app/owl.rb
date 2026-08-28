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

      # No w/h: the owl is drawn from art, so its size comes from the tier
      # descriptor in Assets rather than from the entity. fw/fd stay, since
      # the anchor is still clamped against the screen edge.
      owl.fw = Config::OWL_FW
      owl.fd = Config::OWL_FD

      owl.mode  = :perched
      owl.speed = 0.0

      # Which way it is looking: :east or :west. It turns to face the
      # traveller rather than the way it is going -- an owl watching someone
      # reads as company, and one staring off down its own flight path reads
      # as a bird that happens to be nearby.
      owl.facing = :east

      # Ticks spent flying, wrapped to one full wingbeat. Only ever advances
      # in the air; a perched owl holds a single pose.
      owl.flap_ticks = 0

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
    face_player owl, args.state.player
    beat_wings owl
  end

  # Turns to look at the traveller, snapping to a side profile. He is beside
  # the owl rather than above or below it, so east and west are the only two
  # poses this ever asks for.
  #
  # The deadband is what stops it flicking between facings every frame while
  # he walks along the owl's own x.
  def self.face_player owl, player
    offset = player.x - owl.x

    return if offset.abs < Config::OWL_FACING_DEADBAND_PX

    owl.facing = offset > 0 ? :east : :west
  end

  # A perched owl holds one pose, so the beat only runs in the air and resets
  # on landing -- otherwise it would resume mid-stroke on the next take-off.
  def self.beat_wings owl
    unless owl.mode == :flying
      owl.flap_ticks = 0
      return
    end

    owl.flap_ticks = (owl.flap_ticks + 1) % beat_length
  end

  # One full cycle is both halves of the stroke: wings down, then wings up.
  def self.beat_length
    Config::OWL_FLAP_TICKS * 2
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

  # --- Drawing --------------------------------------------------------------
  #
  # The owl owns which pose it is in; the renderer owns turning that into
  # pixels. Same split as Player.drawable.

  def self.drawable args
    owl = args.state.owl

    {
      entity: owl,
      sprite: sprite_name(owl),
      lift: owl.lift,
      progress: flap_progress(owl)
    }
  end

  def self.sprite_name owl
    if owl.mode == :flying
      owl.facing == :west ? :owl_flying_west : :owl_flying_east
    else
      owl.facing == :west ? :owl_perched_west : :owl_perched_east
    end
  end

  # Normalised 0.0..1.0 through the wingbeat. Assets turns that into a frame
  # without the caller ever learning how many there are, which is what lets
  # the truth-tier owl be drawn with a different number of them later.
  def self.flap_progress owl
    owl.flap_ticks / beat_length.to_f
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
