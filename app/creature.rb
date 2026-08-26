# Creature
#
# An animal that lives in the world -- a deer grazing in a clearing, per the
# story doc. It is NOT an adversary. It cannot damage the player, cannot take
# anything away, and there is no fail state anywhere in this file.
#
# Its role is literal obstruction: sometimes it is standing where the player
# needs to be, in front of something the player needs to see, or beside an
# object the player needs to push. Worst case, it does not move and the player
# tries something else.
#
# Modes:
#   :wandering     walking the circuit between grazing spots
#   :approaching   walking toward where a thrown object landed
#   :lingering     standing at that spot for a beat before resuming
#
# Note that :approaching walks TOWARD the noise, which is curiosity rather than
# the startle the story doc describes ("startle or nudge an animal out of a
# spot the player needs"). That inversion is deliberate for now -- reshaping it
# into a startle is its own step, and doing it here would mean rewriting the
# throw at the same time as stripping the adversarial loop.
module Creature
  def self.defaults args
    args.state.creature ||= args.state.new_entity(:creature) do |creature|
      first = Config::CREATURE_GRAZING_POINTS[0]

      creature.x     = first[0]
      creature.depth = first[1]
      creature.w     = Config::CREATURE_W
      creature.h     = Config::CREATURE_H
      creature.fw    = Config::CREATURE_FW
      creature.fd    = Config::CREATURE_FD

      # Index into CREATURE_GRAZING_POINTS of the spot currently being walked
      # toward. Starting at 1 means the creature immediately heads for the
      # SECOND point rather than standing on the one it spawned on.
      creature.grazing_index = 1

      creature.mode           = :wandering
      creature.approach_x     = 0
      creature.approach_depth = 0
      creature.lingering_until = 0
    end
  end

  def self.update args
    defaults args

    case args.state.creature.mode
    when :wandering   then wander args
    when :approaching then approach args
    when :lingering   then linger args
    end
  end

  # Called by Rock when a thrown object lands. Interrupts whatever the creature
  # was doing -- including an earlier approach, so a second throw redirects it.
  def self.distract args, x, depth
    creature = args.state.creature

    creature.mode           = :approaching
    creature.approach_x     = x
    creature.approach_depth = depth
  end

  def self.wander args
    creature = args.state.creature
    target   = Config::CREATURE_GRAZING_POINTS[creature.grazing_index]

    result = move_toward args, creature, target[0], target[1]
    return if result == :moving

    # :blocked heads for the next spot rather than standing there shoving a
    # box forever. There is no fail state to protect, only a creature that
    # would otherwise look broken -- and wandering off is what an animal that
    # cannot get somewhere would do anyway.
    creature.grazing_index = (creature.grazing_index + 1) % Config::CREATURE_GRAZING_POINTS.length
  end

  def self.approach args
    creature = args.state.creature

    result = move_toward args, creature, creature.approach_x, creature.approach_depth
    return if result == :moving

    # A blocked approach settles where it got to. The noise is still roughly
    # over there, and an animal stopped by an obstacle would not keep walking
    # into it.
    creature.mode            = :lingering
    creature.lingering_until = args.state.tick_count + Config::CREATURE_LINGER_TICKS
  end

  def self.linger args
    creature = args.state.creature
    return if creature.lingering_until > args.state.tick_count

    # Rejoin the circuit at whichever spot is closest, rather than the one it
    # was originally heading for. Without this the creature would often turn
    # around and walk all the way back across the stage, which reads as broken.
    creature.grazing_index = nearest_grazing_index creature
    creature.mode          = :wandering
  end

  # Steps the creature one frame toward (x, depth).
  #
  # Returns :arrived, :moving, or :blocked. Blocked means a pushable is in the
  # way -- the creature is stopped by them but, unlike the player, cannot shift
  # them. It is an animal leaning on a rock, not a bulldozer.
  #
  # The direction vector is normalized before scaling by speed, so the creature
  # covers the same ground per frame on diagonals as on straight runs -- the
  # same reason the player has a DIAGONAL_FACTOR.
  #
  # A wrinkle specific to this game: x is in pixels and depth is in world units,
  # so this vector mixes two scales. That is fine for a circuit authored by eye,
  # but it means "speed" is not one consistent real-world quantity. If the
  # movement ever needs to feel precisely even, normalize depth into
  # pixel-equivalents first.
  def self.move_toward args, creature, target_x, target_depth
    dx = target_x - creature.x
    dd = target_depth - creature.depth

    distance = Math.sqrt((dx * dx) + (dd * dd))

    # Must exceed CREATURE_SPEED, or the creature oversteps every frame and
    # orbits the point forever instead of arriving.
    return :arrived if distance <= Config::CREATURE_ARRIVE_DISTANCE

    next_x     = creature.x + ((dx / distance) * Config::CREATURE_SPEED)
    next_depth = World.clamp_depth(creature.depth + ((dd / distance) * Config::CREATURE_SPEED))

    return :blocked if Pushable.blocks? args, next_x, next_depth, creature

    creature.x     = next_x
    creature.depth = next_depth

    :moving
  end

  def self.nearest_grazing_index creature
    best_index    = 0
    best_distance = nil

    Config::CREATURE_GRAZING_POINTS.each_with_index do |point, index|
      dx = point[0] - creature.x
      dd = point[1] - creature.depth
      distance = (dx * dx) + (dd * dd)   # squared is enough for comparison

      if best_distance.nil? || distance < best_distance
        best_distance = distance
        best_index    = index
      end
    end

    best_index
  end
end
