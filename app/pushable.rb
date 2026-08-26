# Pushable
#
# An object the player moves by walking into it, and which nothing can walk
# through. There is no pick-up and no button: contact plus movement is the
# whole verb.
#
# ALIGNMENT, NOT A SHRUNKEN BOX
#
# A pushable's solid body is what nothing may enter. To actually shift it you
# also have to be lined up with it -- but only ACROSS your direction of travel.
#
#   pushing east:            you make contact as soon as the bodies touch,
#                            but you must be within the shaded depth band
#
#         depth
#           ^   +----------+
#           |   |::::::::::|  <- lined up here: it moves
#      [you]|   |::::::::::|
#           |   +----------+  <- against the rim here: you stop, it does not
#           +---------> x
#
# Insetting the travel axis as well would put that rim IN FRONT of the push
# zone on the way in, and nothing could ever be pushed at all.
#
# HOW A MOVE IS RESOLVED
#
# The player proposes a destination and `resolve` answers with where they
# actually end up, one axis at a time. Anything shifted moves by exactly the
# player's own delta, so the two travel locked together and can never separate
# or interpenetrate.
#
# Axis-at-a-time is doing two jobs: a refused x step leaves the depth step free
# to happen, so running into a face you cannot shift carries you along it
# rather than stopping you dead -- and that is also what lets you slide along
# an object until you are square enough to get purchase on it.
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
      end
    end
  end

  # Runs before Player so the entities exist by the time a move is resolved,
  # and so the renderer never sees a nil list on the first frame.
  def self.update args
    defaults args
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

    axis    = dx.abs < CLAMP_EPSILON ? :depth : :x
    pushed  = []
    blocked = false

    args.state.pushables.each_with_index do |pushable, index|
      if in_push_zone? player, to_x, to_depth, pushable, axis
        pushed << index
      elsif World.would_overlap? to_x, to_depth, player.fw, player.fd, pushable
        # Against the body but not lined up well enough to get purchase on it.
        blocked = true
      end
    end

    return false if blocked
    return false unless pushed.all? { |index| can_move? args, index, dx, dd, pushed }

    pushed.each do |index|
      pushable = args.state.pushables[index]

      pushable.x     += dx
      pushable.depth += dd
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
end
