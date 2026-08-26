# Pushable
#
# An object the player moves by walking into it, and which nothing can walk
# through. There is no pick-up and no button: contact plus movement is the
# whole verb.
#
# ALIGNMENT, AND WALKING PAST
#
# To shift a pushable you have to be lined up with it ACROSS your direction of
# travel. Walking east, that means being within a depth band; miss the band and
# you walk straight past, in front of or behind the thing.
#
#         depth
#           ^   +----------+
#           |   |          |  <- off the band: you pass by, it does not move
#           |   |::::::::::|  <- on the band: it moves
#      [you]|   |          |
#           |   +----------+
#           +---------> x
#
# Passing by rather than being stopped is the point. A 2.5D stage means being
# at a different depth from something is a real spatial fact, not a near miss,
# so an object you are not squared up to should not be a wall.
#
# You still cannot walk THROUGH one: the middle of it is the push zone, and
# entering that either shifts the object or, if it has nowhere to go, stops
# you.
#
# Insetting the travel axis as well would put a dead rim IN FRONT of the push
# zone on the way in, and nothing could ever be pushed at all.
#
# HOW A MOVE IS RESOLVED
#
# The player proposes a destination and `resolve` answers with where they
# actually end up, one axis at a time. Anything shifted moves by exactly the
# player's own delta, so the two travel locked together and can never separate
# or interpenetrate.
#
# Axis-at-a-time is what gives sliding: a refused x step leaves the depth step
# free to happen, so leaning on something you cannot shift carries you along it
# rather than stopping you dead.
#
# WHAT REFUSES A PUSH
#
#   - the edge of the stage
#   - another pushable
#   - the creature
#
# The last is a design requirement rather than a physics one: the story doc
# wants an animal that is sometimes standing where you need to push something,
# so that clearing it with a thrown object is worth doing.
module Pushable
  # Authored positions, kept here rather than in Config for the same reason as
  # Seams: Config holds values tuned by feel, and these are placements that
  # will be moved around constantly while designing a pattern.
  #
  # Both sit in :far_stand, the region whose seam already exists.
  PUSHABLES = [
    { x: 400, depth: 200.0, w: 40, h: 40, fw: 44, fd: 30 },
    { x: 620, depth: 230.0, w: 40, h: 40, fw: 44, fd: 30 }
  ]

  # Clamping returns a float that may differ from the requested value only by
  # rounding, so "did the clamp actually stop me" needs a tolerance rather than
  # an equality test.
  CLAMP_EPSILON = 0.001

  def self.defaults args
    args.state.pushables ||= PUSHABLES.map do |pushable|
      args.state.new_entity(:pushable) do |entity|
        entity.x     = pushable[:x]
        entity.depth = pushable[:depth]
        entity.w     = pushable[:w]
        entity.h     = pushable[:h]
        entity.fw    = pushable[:fw]
        entity.fd    = pushable[:fd]

        # How far BEHIND its true position the object is drawn. Presentation
        # only -- see settle_lag. Nothing in the simulation reads these.
        entity.lag_x     = 0.0
        entity.lag_depth = 0.0

        # Where a thrown object has sent it, and whether it is still on its
        # way there. See react/drift.
        entity.drifting     = false
        entity.target_x     = 0.0
        entity.target_depth = 0.0
      end
    end
  end

  # Runs before Player so the entities exist by the time a move is resolved,
  # and so the renderer never sees a nil list on the first frame.
  def self.update args
    defaults args

    args.state.pushables.each_with_index do |pushable, index|
      settle_lag pushable
      drift args, pushable, index
    end
  end

  # --- Reacting to a thrown object -----------------------------------------
  #
  # A pushable that moves itself is a design choice rather than physics: it
  # makes these objects read as faintly alive, and it gives the throw a use
  # beyond the creature. Which way it goes depends on what was thrown.
  #
  # It is much slower than a push, and the distance is short. Luring something
  # into place should be the imprecise, patient option next to walking over and
  # shoving it exactly where you want it -- otherwise the throw would simply be
  # a better push.

  def self.react args, x, depth, effect
    defaults args

    args.state.pushables.each do |pushable|
      next unless near? pushable, x, depth

      travel = effect == :attract ? Config::PUSHABLE_ATTRACT_DISTANCE : Config::PUSHABLE_REPEL_DISTANCE

      # A landing dead-centre on an object leaves no direction; nudging it
      # along x is arbitrary but never happens twice in the same place, and
      # the alternative is silently ignoring the throw.
      dx, dd = Throwables.direction effect, x, depth, pushable.x, pushable.depth, [1.0, 0.0]

      pushable.drifting     = true
      pushable.target_x     = (pushable.x + (dx * travel)).clamp(0, Config::SCREEN_W)
      pushable.target_depth = World.clamp_depth(pushable.depth + (dd * travel))
    end
  end

  def self.near? pushable, x, depth
    dx = pushable.x - x
    dd = pushable.depth - depth

    Math.sqrt((dx * dx) + (dd * dd)) <= Config::PUSHABLE_REACT_RADIUS
  end

  # One frame of self-propelled movement. Stops on arrival, and equally on
  # being blocked -- an object that cannot get where it was called to simply
  # stays, the same way a boxed-in creature does.
  def self.drift args, pushable, index
    return unless pushable.drifting

    dx = pushable.target_x - pushable.x
    dd = pushable.target_depth - pushable.depth

    distance = Math.sqrt((dx * dx) + (dd * dd))

    if distance <= Config::PUSHABLE_ARRIVE_DISTANCE
      pushable.drifting = false
      return
    end

    step_x = (dx / distance) * Config::PUSHABLE_DRIFT_SPEED
    step_d = (dd / distance) * Config::PUSHABLE_DRIFT_SPEED

    next_x     = pushable.x + step_x
    next_depth = pushable.depth + step_d

    unless can_drift? args, pushable, index, next_x, next_depth
      pushable.drifting = false
      return
    end

    pushable.x     = next_x
    pushable.depth = next_depth
  end

  # Drifting answers to everything a push does, plus the player -- an object
  # moving under its own steam has no business shoving him around.
  def self.can_drift? args, pushable, index, x, depth
    return false unless within_stage? pushable, x, depth
    return false if obstructed? args, pushable, index, x, depth, []

    !World.would_overlap?(x, depth, pushable.fw, pushable.fd, args.state.player)
  end

  # Eases the drawn position back toward the true one.
  #
  # A pushed object's real position stays locked to the player, which is what
  # makes collision exact without a resolution step. Drawing it exactly there
  # too made it slide like a decal stuck to his hands. Instead the drawing
  # trails and catches up, so the thing gives a little under the hand and
  # settles when he stops.
  #
  # Runs before Player, so lag added by this frame's push decays starting next
  # frame rather than being wiped the instant it appears.
  def self.settle_lag pushable
    pushable.lag_x     *= Config::PUSH_LAG_DECAY
    pushable.lag_depth *= Config::PUSH_LAG_DECAY
  end

  # Where the player actually ends up, given where they would like to go.
  # Returns [x, depth]. Shifts whatever it can as a side effect, and sets
  # player.pushing, which is what selects the push sprite.
  def self.resolve args, player, x, depth
    at_x     = player.x
    at_depth = player.depth

    at_x     = x     if step args, player, at_x, at_depth, x, at_depth
    at_depth = depth if step args, player, at_x, at_depth, at_x, depth

    [at_x, at_depth]
  end

  # Tries to move the player from one point to another along a single axis,
  # shifting anything it can. Commits every move or none of them: a partial
  # commit would leave an object shoved for a step that did not happen.
  def self.step args, player, from_x, from_depth, to_x, to_depth
    dx = to_x - from_x
    dd = to_depth - from_depth

    return true if dx.abs < CLAMP_EPSILON && dd.abs < CLAMP_EPSILON

    axis   = dx.abs < CLAMP_EPSILON ? :depth : :x
    pushed = []

    args.state.pushables.each_with_index do |pushable, index|
      pushed << index if in_push_zone? player, to_x, to_depth, pushable, axis
    end

    # Overlapping the body without reaching the push zone is deliberately NOT
    # a refusal -- that is walking past the thing. Only an object you have
    # actually got hold of, and which has nowhere to go, stops you.
    return false unless pushed.all? { |index| can_move? args, index, dx, dd, pushed }

    pushed.each do |index|
      pushable = args.state.pushables[index]

      pushable.x     += dx
      pushable.depth += dd

      # Being shoved overrides being called: the player has hold of it now.
      pushable.drifting = false

      # The drawing stays where it was and catches up over the next few
      # frames. Clamped so a restart or a hot-reload jump cannot fling it.
      pushable.lag_x     = (pushable.lag_x - dx).clamp(-Config::PUSH_LAG_MAX, Config::PUSH_LAG_MAX)
      pushable.lag_depth = (pushable.lag_depth - dd).clamp(-Config::PUSH_LAG_MAX, Config::PUSH_LAG_MAX)
    end

    player.pushing = true unless pushed.empty?

    true
  end

  def self.can_move? args, index, dx, dd, pushed
    pushable = args.state.pushables[index]

    target_x     = pushable.x + dx
    target_depth = pushable.depth + dd

    return false unless within_stage? pushable, target_x, target_depth

    !obstructed? args, pushable, index, target_x, target_depth, pushed
  end

  # A pushable is at the stage edge when clamping would move it, which is the
  # same bound the player is held to.
  def self.within_stage? pushable, x, depth
    clamped_x     = World.clamp_x x, pushable.fw, depth
    clamped_depth = World.clamp_depth depth

    (clamped_x - x).abs < CLAMP_EPSILON && (clamped_depth - depth).abs < CLAMP_EPSILON
  end

  # `pushed` are the objects moving on this same step. They all travel by the
  # identical delta, so their positions relative to each other cannot change
  # and they can never be what blocks each other.
  def self.obstructed? args, pushable, index, x, depth, pushed
    return true if blocked_by_creature? args, pushable, x, depth

    args.state.pushables.each_with_index do |other, other_index|
      next if other_index == index
      next if pushed.include? other_index
      return true if World.would_overlap? x, depth, pushable.fw, pushable.fd, other
    end

    false
  end

  # Creature.update runs after Player, so on the very first frame the creature
  # does not exist yet and nothing can be blocked by it.
  def self.blocked_by_creature? args, pushable, x, depth
    creature = args.state.creature
    return false unless creature

    World.would_overlap? x, depth, pushable.fw, pushable.fd, creature
  end

  def self.in_push_zone? player, x, depth, pushable, axis
    World.footprint_at(x, depth, player.fw, player.fd)
         .intersect_rect? push_zone(pushable, axis)
  end

  # Inset only across the direction of travel. See the note at the top of the
  # file for why insetting both axes makes everything unpushable.
  def self.push_zone pushable, axis
    if axis == :x
      World.footprint_at pushable.x, pushable.depth,
                         pushable.fw,
                         pushable.fd - (Config::PUSH_CONTACT_INSET_DEPTH * 2)
    else
      World.footprint_at pushable.x, pushable.depth,
                         pushable.fw - (Config::PUSH_CONTACT_INSET_X * 2),
                         pushable.fd
    end
  end

  # Would an entity-sized box at this spot be inside a pushable? Used by the
  # creature, which is stopped by the solid body but cannot shift it.
  def self.blocks? args, x, depth, entity
    defaults args

    args.state.pushables.each do |pushable|
      return true if World.would_overlap? x, depth, entity.fw, entity.fd, pushable
    end

    false
  end

  # An arrive distance at or below the step size means a drifting object
  # oversteps its target every frame and circles it forever.
  def self.assert_arrive_distance_exceeds_drift!
    return if Config::PUSHABLE_ARRIVE_DISTANCE > Config::PUSHABLE_DRIFT_SPEED

    raise "PUSHABLE_ARRIVE_DISTANCE (#{Config::PUSHABLE_ARRIVE_DISTANCE}) must exceed PUSHABLE_DRIFT_SPEED (#{Config::PUSHABLE_DRIFT_SPEED})"
  end

  # An inset at or past the half-width would leave a push zone of zero or
  # negative size, and the object would silently become unpushable. Refuse to
  # start instead -- the same stance Regions takes on overlapping bounds.
  # Runs on load, and therefore again on every hot-reload of this file.
  def self.assert_push_zones_exist!
    PUSHABLES.each do |pushable|
      if pushable[:fw] <= Config::PUSH_CONTACT_INSET_X * 2
        raise "PUSH_CONTACT_INSET_X (#{Config::PUSH_CONTACT_INSET_X}) leaves no push zone in fw #{pushable[:fw]}"
      end

      if pushable[:fd] <= Config::PUSH_CONTACT_INSET_DEPTH * 2
        raise "PUSH_CONTACT_INSET_DEPTH (#{Config::PUSH_CONTACT_INSET_DEPTH}) leaves no push zone in fd #{pushable[:fd]}"
      end
    end
  end

  assert_push_zones_exist!
  assert_arrive_distance_exceeds_drift!
end
