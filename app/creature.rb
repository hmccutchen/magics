# Creature
#
# An animal that lives in the world -- a deer grazing in a clearing, per the
# story doc. It is NOT an adversary. It cannot damage the player, cannot take
# anything away, and there is no fail state anywhere in this file.
#
# Its role is literal obstruction: sometimes it is standing where the player
# needs to be, in front of something the player needs to see, or beside an
# object the player needs to push. A thrown object landing nearby either draws
# it over or sends it off, depending on what was thrown, and that is how the
# player asks it to move.
#
# Moving it is the ENTIRE interaction. Nothing here scores, damages, or fails.
# If the creature has nowhere to go it simply stays put and the player tries
# again or finds another way -- the story doc calls that out as the acceptable
# worst case, not a dead end to design around.
#
# Modes:
#   :wandering    walking the circuit between grazing spots
#   :approaching  wandering over to something that landed nearby
#   :fleeing      bolting away from something that landed nearby
#   :settling     standing still afterwards, before returning to grazing
#
# Which of the two a landing produces depends on what was thrown -- see
# Throwables. Curiosity is as useful as alarm here: drawing the animal ONTO a
# spot is how you get it off a different one.
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
      creature.target_x       = 0
      creature.target_depth   = 0
      creature.settling_until = 0
    end
  end

  def self.update args
    defaults args

    case args.state.creature.mode
    when :wandering   then wander args
    when :approaching then head_to_landing args
    when :fleeing     then flee args
    when :settling    then settle args
    end
  end

  # Called by Rock when a thrown object lands.
  #
  # Ignored unless the landing was close enough to notice, which is what keeps
  # the throw a way of moving the animal off a particular spot rather than a
  # remote control that works from anywhere on the stage.
  #
  # Interrupts whatever it was doing, including an earlier reaction, so a
  # second throw redirects it.
  def self.react args, x, depth, effect
    creature = args.state.creature
    return unless near? creature, x, depth

    if effect == :attract
      creature.mode         = :approaching
      creature.target_x     = x
      creature.target_depth = depth
      return
    end

    dx, dd = Throwables.direction effect, x, depth, creature.x, creature.depth,
                                  away_from_player(args, creature)

    creature.mode         = :fleeing
    creature.target_x     = (creature.x + (dx * Config::CREATURE_FLEE_DISTANCE))
                            .clamp(0, Config::SCREEN_W)
    creature.target_depth = World.clamp_depth(
      creature.depth + (dd * Config::CREATURE_FLEE_DISTANCE)
    )
  end

  def self.near? creature, x, depth
    dx = creature.x - x
    dd = creature.depth - depth

    Math.sqrt((dx * dx) + (dd * dd)) <= Config::CREATURE_STARTLE_RADIUS
  end

  # Fallback direction for a pebble that lands exactly on the creature, leaving
  # no vector to work from: it reacts relative to the player instead, which is
  # where the thing came from and reads better than a fixed compass direction.
  def self.away_from_player args, creature
    player = args.state.player

    dx = creature.x - player.x
    dd = creature.depth - player.depth

    distance = Math.sqrt((dx * dx) + (dd * dd))
    return [1.0, 0.0] if distance <= 0.001

    [dx / distance, dd / distance]
  end

  def self.wander args
    creature = args.state.creature
    target   = Config::CREATURE_GRAZING_POINTS[creature.grazing_index]

    result = move_toward args, creature, target[0], target[1], Config::CREATURE_SPEED
    return if result == :moving

    # :blocked heads for the next spot rather than standing there shoving a
    # box forever. There is no fail state to protect, only a creature that
    # would otherwise look broken -- and wandering off is what an animal that
    # cannot get somewhere would do anyway.
    creature.grazing_index = (creature.grazing_index + 1) % Config::CREATURE_GRAZING_POINTS.length
  end

  # Curiosity, at grazing pace -- an animal wandering over to see what fell,
  # not charging it.
  def self.head_to_landing args
    creature = args.state.creature

    result = move_toward args, creature, creature.target_x, creature.target_depth, Config::CREATURE_SPEED
    return if result == :moving

    creature.mode           = :settling
    creature.settling_until = args.state.tick_count + Config::CREATURE_SETTLE_TICKS
  end

  def self.flee args
    creature = args.state.creature

    result = move_toward args, creature, creature.target_x, creature.target_depth, Config::CREATURE_FLEE_SPEED
    return if result == :moving

    # Arriving and being blocked both end the bolt. A creature boxed in stops
    # where it got to -- the throw simply did not achieve much, which the story
    # doc names as the acceptable worst case.
    creature.mode           = :settling
    creature.settling_until = args.state.tick_count + Config::CREATURE_SETTLE_TICKS
  end

  def self.settle args
    creature = args.state.creature
    return if creature.settling_until > args.state.tick_count

    # Rejoin the circuit at whichever spot is closest, rather than the one it
    # was originally heading for. Without this the creature would often turn
    # around and walk all the way back across the stage, which reads as broken.
    creature.grazing_index = nearest_grazing_index creature
    creature.mode          = :wandering
  end

  # Steps the creature one frame toward (x, depth) at the given speed.
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
  def self.move_toward args, creature, target_x, target_depth, speed
    dx = target_x - creature.x
    dd = target_depth - creature.depth

    distance = Math.sqrt((dx * dx) + (dd * dd))

    return :arrived if distance <= Config::CREATURE_ARRIVE_DISTANCE

    next_x     = creature.x + ((dx / distance) * speed)
    next_depth = World.clamp_depth(creature.depth + ((dd / distance) * speed))

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

  # An arrive distance at or below the step size means the creature oversteps
  # its target every frame and circles it forever, which looks like a bug in
  # the pathing rather than a mistuned constant. Refuse to start instead.
  # Runs on load, and therefore again on every hot-reload of this file.
  def self.assert_arrive_distance_exceeds_speeds!
    fastest = [Config::CREATURE_SPEED, Config::CREATURE_FLEE_SPEED].max
    return if Config::CREATURE_ARRIVE_DISTANCE > fastest

    raise "CREATURE_ARRIVE_DISTANCE (#{Config::CREATURE_ARRIVE_DISTANCE}) must exceed the fastest creature speed (#{fastest})"
  end

  assert_arrive_distance_exceeds_speeds!
end
