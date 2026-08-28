# Owl
#
# A companion that moves through the same world-space as everything else, per
# the existing (x, depth) convention -- not a UI overlay and not a dialogue
# box. That choice is what lets it go through Assets/Regions like every other
# entity: Renderer resolves fidelity from an entity's ground position, so an
# owl WITHOUT one could never be told what tier to draw at.
#
# It does not stand on the floor. Its (x, depth) is the spot on the ground it
# is ABOVE, and `lift` raises the drawn sprite off that spot -- the same
# mechanism the thrown rock uses to look airborne while still sorting by where
# it is on the ground. Depth sorting therefore keeps working unchanged: an owl
# high in the air still passes behind whatever is nearer the camera than the
# ground beneath it.
#
# --- What it does -----------------------------------------------------------
#
# It SOARS, high above the traveller, and that is where it spends most of its
# life. It follows him with SLACK rather than a fixed offset: he has to walk
# far enough to open a gap before the owl bothers to close it, so it is
# usually ahead of him or catching up, rarely exactly overhead. That reads as
# something keeping its own company rather than a cursor stuck to his shoulder.
#
# Every so often it comes down and lands on something -- a crate, the deer --
# sits there a while, and climbs back up. It never lands on the traveller.
# Whatever it perches on, it RIDES: push the crate and the owl goes with it,
# and it will sit on the deer while the deer wanders off. An owl that stayed
# nailed in place while its perch slid out from under it would read as a bug.
#
# Wingbeats are reserved for getting down to a perch and back off one. Soaring
# is a glide, so crossing open air to catch the traveller up happens on
# motionless wings -- which is what birds actually do, and what keeps the
# flapping meaningful when it does happen.
#
# Modes:
#   :soaring     gliding high, following him. The default and the usual state.
#   :descending  beating down toward a chosen perch
#   :perched     sitting on it, riding wherever it goes
#   :climbing    beating back up to soaring height
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

      owl.mode  = :soaring
      owl.speed = 0.0

      # Which way it is looking: :east or :west. It turns to face the
      # traveller rather than the way it is going -- an owl watching someone
      # reads as company, and one staring off down its own flight path reads
      # as a bird that happens to be nearby.
      owl.facing = :east

      # Ticks spent beating its wings, wrapped to one full stroke. Only
      # advances while flapping; a gliding or perched owl holds one pose.
      owl.flap_ticks = 0

      owl.lift = Config::OWL_SOAR_LIFT

      # What it is sitting on, held as a KIND and an INDEX rather than as a
      # reference to the entity. args.state survives a hot-reload while the
      # entities in it are rebuilt, so a stored reference would go stale and
      # point at an object no longer in the world. Two plain values re-resolve
      # against whatever is there now.
      owl.perch_kind  = nil
      owl.perch_index = 0

      # Ticks at which the current soar or perch runs out. Both randomised, so
      # the rhythm does not come out metronomic -- the same reason the
      # creature's grazing is.
      owl.soar_until  = 0
      owl.perch_until = 0
    end
  end

  # Runs after Player, so it chases where the player IS this frame rather than
  # trailing a frame behind him.
  def self.update args
    defaults args

    owl = args.state.owl

    case owl.mode
    when :soaring    then soar args, owl
    when :descending then descend args, owl
    when :perched    then ride args, owl
    when :climbing   then climb args, owl
    end

    face_player owl, args.state.player
    beat_wings owl
  end

  # --- Soaring --------------------------------------------------------------

  def self.soar args, owl
    follow args, owl, Config::OWL_SPEED
    ease_lift owl, Config::OWL_SOAR_LIFT

    return if args.state.tick_count < owl.soar_until

    perch = choose_perch args
    return start_soaring args, owl if perch.nil?

    owl.mode        = :descending
    owl.perch_kind  = perch[:kind]
    owl.perch_index = perch[:index]
  end

  # Closes the gap to the anchor, but only once it is worth crossing. The
  # slack radius is the entire difference between a companion and a fixed
  # offset: below it the owl simply drifts while the traveller mills about.
  def self.follow args, owl, cruise
    anchor   = anchor_for args.state.player
    distance = distance_to owl, anchor

    if distance <= Config::OWL_SLACK_RADIUS
      owl.speed = 0.0
      return
    end

    move_toward owl, anchor, distance, cruise
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

  # --- Coming down and going back up ----------------------------------------

  def self.descend args, owl
    perch = perch_entity args, owl

    # Whatever it had picked is gone -- a restart, or a shape change that
    # rebuilt the entities. Go back up rather than descending onto nothing.
    return climb_away owl if perch.nil?

    target = [perch.x, perch.depth]

    move_toward owl, target, distance_to(owl, target), Config::OWL_LANDING_SPEED
    ease_lift owl, perch_lift(perch)

    return unless landed? owl, perch

    owl.mode        = :perched
    owl.perch_until = args.state.tick_count + span(
      Config::OWL_PERCH_TICKS_MIN, Config::OWL_PERCH_TICKS_MAX
    )
  end

  # It has to be both over the thing and down at its height. Checking only the
  # ground position would snap the owl onto a crate while it was still well
  # above it.
  def self.landed? owl, perch
    return false if distance_to(owl, [perch.x, perch.depth]) > Config::OWL_ARRIVE_DISTANCE

    (owl.lift - perch_lift(perch)).abs <= Config::OWL_LIFT_ARRIVED_PX
  end

  def self.climb args, owl
    follow args, owl, Config::OWL_LANDING_SPEED
    ease_lift owl, Config::OWL_SOAR_LIFT

    return if (owl.lift - Config::OWL_SOAR_LIFT).abs > Config::OWL_LIFT_ARRIVED_PX

    start_soaring args, owl
  end

  def self.climb_away owl
    owl.mode       = :climbing
    owl.perch_kind = nil
  end

  def self.start_soaring args, owl
    owl.mode       = :soaring
    owl.perch_kind = nil
    owl.soar_until = args.state.tick_count + span(
      Config::OWL_SOAR_TICKS_MIN, Config::OWL_SOAR_TICKS_MAX
    )
  end

  # --- Perching -------------------------------------------------------------

  # Sitting on something is not standing still: the owl takes the thing's
  # position every frame, so a crate being shoved carries it along and the
  # deer walks off wearing it.
  def self.ride args, owl
    perch = perch_entity args, owl
    return climb_away owl if perch.nil?

    owl.x     = perch.x
    owl.depth = perch.depth
    owl.speed = 0.0

    ease_lift owl, perch_lift(perch)

    # Two ways off: it has sat long enough, or the traveller has gone far
    # enough that following him matters more than sitting here. The second is
    # what keeps following the dominant behaviour rather than something the
    # owl forgets about while it rests.
    return climb_away owl if args.state.tick_count >= owl.perch_until
    return unless too_far_from? args, owl

    climb_away owl
  end

  def self.too_far_from? args, owl
    distance_to(owl, anchor_for(args.state.player)) > Config::OWL_SLACK_RADIUS
  end

  # Sits on TOP of the thing, so the height comes from how tall it is drawn
  # where it stands -- a crate at the back of the stage is a lower perch than
  # the same crate at the front.
  def self.perch_lift perch
    perch.h * World.scale(perch.depth)
  end

  # Everything in the world it is willing to land on. Explicitly NOT the
  # traveller: the owl accompanies him, it does not sit on him.
  def self.perchables args
    list = args.state.pushables.each_with_index.map do |pushable, index|
      { kind: :pushable, index: index, entity: pushable }
    end

    creature = args.state.creature
    list << { kind: :creature, index: 0, entity: creature } if creature

    list
  end

  # The nearest thing worth landing on, measured from the TRAVELLER rather
  # than from the owl, so it never peels off across the map to sit on
  # something he has already walked away from. Nil means nothing qualifies and
  # the owl simply keeps soaring.
  def self.choose_perch args
    player = args.state.player
    best   = nil
    best_d = nil

    perchables(args).each do |candidate|
      d = distance_to_entity player, candidate[:entity]
      next if d > Config::OWL_PERCH_REACH
      next if best_d && d >= best_d

      best   = candidate
      best_d = d
    end

    best
  end

  def self.perch_entity args, owl
    case owl.perch_kind
    when :pushable then args.state.pushables[owl.perch_index]
    when :creature then args.state.creature
    end
  end

  # --- Movement -------------------------------------------------------------

  # Nothing blocks the owl: it is in the air, so pushables and the creature
  # are beneath it. This is deliberately NOT the creature's move_toward --
  # that one collision-checks against the ground plane, which would stop a
  # flying bird dead on a crate, and landing on crates is the entire point.
  def self.move_toward owl, target, distance, cruise
    if distance <= Config::OWL_ARRIVE_DISTANCE
      owl.speed = 0.0
      return
    end

    owl.speed = eased_speed owl, distance, cruise

    owl.x     += ((target[0] - owl.x) / distance) * owl.speed
    owl.depth  = World.clamp_depth(
      owl.depth + (((target[1] - owl.depth) / distance) * owl.speed)
    )
  end

  # Ramp up from rest, ease down over the last stretch so it settles onto a
  # perch instead of stopping dead. Floored so the curve cannot approach zero
  # and leave it drifting in forever.
  def self.eased_speed owl, distance, cruise
    ceiling = cruise
    ceiling = cruise * (distance / Config::OWL_SLOWDOWN_DISTANCE) if distance < Config::OWL_SLOWDOWN_DISTANCE
    ceiling = Config::OWL_MIN_SPEED if ceiling < Config::OWL_MIN_SPEED

    stepped = owl.speed + Config::OWL_ACCELERATION

    stepped > ceiling ? ceiling : stepped
  end

  # Moves a fixed fraction of the remaining gap each frame, so it leaves a
  # perch quickly and arrives gently -- and never overshoots, whatever the
  # heights are retuned to.
  def self.ease_lift owl, target
    owl.lift += (target - owl.lift) * Config::OWL_LIFT_EASE
  end

  # --- Facing and wings -----------------------------------------------------

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

  # Wings beat only on the way down to a perch and on the way back up. A
  # soaring owl glides and a perched one sits, so both hold a single pose --
  # and the beat resets, so it does not resume mid-stroke next time.
  def self.beat_wings owl
    unless flapping? owl
      owl.flap_ticks = 0
      return
    end

    owl.flap_ticks = (owl.flap_ticks + 1) % beat_length
  end

  def self.flapping? owl
    owl.mode == :descending || owl.mode == :climbing
  end

  # One full cycle is both halves of the stroke: wings down, then wings up.
  def self.beat_length
    Config::OWL_FLAP_TICKS * 2
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
    west = owl.facing == :west

    if flapping? owl
      west ? :owl_flying_west : :owl_flying_east
    elsif owl.mode == :perched
      west ? :owl_perched_west : :owl_perched_east
    else
      west ? :owl_soaring_west : :owl_soaring_east
    end
  end

  # Normalised 0.0..1.0 through the wingbeat. Assets turns that into a frame
  # without the caller ever learning how many there are, which is what lets
  # the truth-tier owl be drawn with a different number of them later.
  def self.flap_progress owl
    owl.flap_ticks / beat_length.to_f
  end

  # --- Shared helpers -------------------------------------------------------
  #
  # Mixed units, the same caveat the creature's circuit carries: x is pixels
  # and depth is world units, so these magnitudes are not one consistent
  # real-world quantity. They drive how a bird decides to move, not physics,
  # so eyeballed is fine.

  def self.distance_to owl, target
    dx = target[0] - owl.x
    dd = target[1] - owl.depth

    Math.sqrt((dx * dx) + (dd * dd))
  end

  def self.distance_to_entity a, b
    dx = a.x - b.x
    dd = a.depth - b.depth

    Math.sqrt((dx * dx) + (dd * dd))
  end

  # A randomised duration in ticks, the same shape the creature's grazing
  # uses, so neither the soaring nor the sitting comes out metronomic.
  def self.span low, high
    low + rand(high - low)
  end

  # --- Authoring guards -----------------------------------------------------
  #
  # All run on load, and therefore again on every hot-reload of this file --
  # which is exactly when a hand-tuned constant is most likely to be wrong.

  # An arrive distance at or below the step size means the owl oversteps its
  # target every frame and circles it forever, which reads as a bug in the
  # following rather than a mistuned constant.
  def self.assert_arrive_distance_exceeds_speed!
    fastest = [Config::OWL_SPEED, Config::OWL_LANDING_SPEED].max
    return if Config::OWL_ARRIVE_DISTANCE > fastest

    raise "OWL_ARRIVE_DISTANCE (#{Config::OWL_ARRIVE_DISTANCE}) must exceed the fastest owl speed (#{fastest})"
  end

  # A floor above the arrive distance steps past the target every frame, which
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

  # A perch reach shorter than the slack radius would let the owl land on
  # something and be judged too far from the traveller on the very next frame,
  # so it would bounce straight back up without ever settling.
  def self.assert_perch_reach_exceeds_slack!
    return if Config::OWL_PERCH_REACH > Config::OWL_SLACK_RADIUS

    raise "OWL_PERCH_REACH (#{Config::OWL_PERCH_REACH}) must exceed OWL_SLACK_RADIUS (#{Config::OWL_SLACK_RADIUS})"
  end

  # Randomised spans are drawn with rand(high - low), which raises on a
  # negative argument and returns 0 for an empty range -- a fixed duration
  # wearing the costume of a randomised one.
  def self.assert_spans_are_ranges!
    [
      ['soar', Config::OWL_SOAR_TICKS_MIN, Config::OWL_SOAR_TICKS_MAX],
      ['perch', Config::OWL_PERCH_TICKS_MIN, Config::OWL_PERCH_TICKS_MAX]
    ].each do |name, low, high|
      next if high > low

      raise "OWL_#{name.upcase}_TICKS_MAX (#{high}) must exceed _MIN (#{low})"
    end
  end

  assert_arrive_distance_exceeds_speed!
  assert_min_speed_arrives!
  assert_slack_exceeds_arrive_distance!
  assert_perch_reach_exceeds_slack!
  assert_spans_are_ranges!
end
