# Pushable
#
# An object the player moves by walking into it, and which nothing can walk
# through. There is no pick-up and no button: contact plus movement is the
# whole verb.
#
# HOW IT MOVES
#
# The player asks `resolve` where it is allowed to end up before committing a
# move. Anything in the way is pushed by exactly the player's own delta, so the
# two travel locked together and can never separate or interpenetrate. If a
# pushable cannot take that step, neither can the player.
#
# WHAT BLOCKS A PUSH
#
#   - the edge of the stage
#   - another pushable
#   - the creature
#
# The last of those is a design requirement rather than a physics one: the
# story doc wants an animal that is sometimes standing where you need to push
# something, so that clearing it with a thrown object is worth doing.
#
# A blocked push stops the player entirely for that frame rather than letting
# them slide along the obstruction. Sliding is the nicer feel and is a thing to
# add later; stopping is the honest simple version and never lets anything end
# up inside anything else.
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
  # Returns [x, depth]. Pushes whatever is in the way as a side effect, and
  # sets player.pushing, which is what selects the push sprite.
  def self.resolve args, player, x, depth
    dx = x - player.x
    dd = depth - player.depth

    args.state.pushables.each_with_index do |pushable, index|
      next unless World.would_overlap? x, depth, player.fw, player.fd, pushable
      return [player.x, player.depth] unless push args, pushable, index, dx, dd

      player.pushing = true
    end

    [x, depth]
  end

  # Moves one pushable by (dx, dd) if it can go there. Returns false when it
  # cannot, which is what stops the player.
  def self.push args, pushable, index, dx, dd
    target_x     = pushable.x + dx
    target_depth = pushable.depth + dd

    return false unless within_stage? pushable, target_x, target_depth
    return false if obstructed? args, pushable, index, target_x, target_depth

    pushable.x     = target_x
    pushable.depth = target_depth

    true
  end

  # A pushable is at the stage edge when clamping would move it, which is the
  # same bound the player is held to.
  def self.within_stage? pushable, x, depth
    clamped_x     = World.clamp_x x, pushable.fw, depth
    clamped_depth = World.clamp_depth depth

    (clamped_x - x).abs < CLAMP_EPSILON && (clamped_depth - depth).abs < CLAMP_EPSILON
  end

  def self.obstructed? args, pushable, index, x, depth
    return true if blocked_by_creature? args, pushable, x, depth

    args.state.pushables.each_with_index do |other, other_index|
      next if other_index == index
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

  # Would an entity-sized box at this spot be inside a pushable? Used by the
  # creature, which is stopped by pushables but cannot push them.
  def self.blocks? args, x, depth, entity
    defaults args

    args.state.pushables.each do |pushable|
      return true if World.would_overlap? x, depth, entity.fw, entity.fd, pushable
    end

    false
  end
end
