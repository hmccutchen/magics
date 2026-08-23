# Enemy
#
# Walks a fixed waypoint circuit, investigates thrown rocks, and strips the
# item's effect on contact.
#
# It never damages or kills -- catching the player only takes away what they
# were carrying. This is an avoidance game, not a combat one. The rock is the
# counterplay: it cannot hurt the enemy, only relocate its attention.
#
# Modes:
#   :patrolling    walking the circuit
#   :investigating walking toward where a rock landed
#   :inspecting    standing at the landing spot for a beat
#
# The enemy is still dangerous in every mode -- being distracted does not make
# it safe to walk through, only easier to walk around.
module Enemy
  def self.defaults args
    args.state.enemy ||= args.state.new_entity(:enemy) do |enemy|
      first = Config::ENEMY_PATROL_POINTS[0]

      enemy.x     = first[0]
      enemy.depth = first[1]
      enemy.w     = Config::ENEMY_W
      enemy.h     = Config::ENEMY_H
      enemy.fw    = Config::ENEMY_FW
      enemy.fd    = Config::ENEMY_FD

      # Index into ENEMY_PATROL_POINTS of the waypoint currently being walked
      # toward. Starting at 1 means the enemy immediately heads for the SECOND
      # point rather than standing on the one it spawned on.
      enemy.patrol_index = 1

      enemy.mode              = :patrolling
      enemy.investigate_x     = 0
      enemy.investigate_depth = 0
      enemy.inspecting_until  = 0
    end
  end

  def self.update args
    defaults args

    case args.state.enemy.mode
    when :patrolling    then patrol args
    when :investigating then investigate args
    when :inspecting    then inspect_spot args
    end

    check_contact args
  end

  # Called by Rock when a thrown rock lands. Interrupts whatever the enemy was
  # doing -- including an earlier investigation, so a second throw redirects it.
  def self.distract args, x, depth
    enemy = args.state.enemy

    enemy.mode              = :investigating
    enemy.investigate_x     = x
    enemy.investigate_depth = depth
  end

  def self.patrol args
    enemy  = args.state.enemy
    target = Config::ENEMY_PATROL_POINTS[enemy.patrol_index]

    return unless move_toward enemy, target[0], target[1]

    enemy.patrol_index = (enemy.patrol_index + 1) % Config::ENEMY_PATROL_POINTS.length
  end

  def self.investigate args
    enemy = args.state.enemy

    return unless move_toward enemy, enemy.investigate_x, enemy.investigate_depth

    enemy.mode             = :inspecting
    enemy.inspecting_until = args.state.tick_count + Config::ENEMY_INVESTIGATE_TICKS
  end

  def self.inspect_spot args
    enemy = args.state.enemy
    return if enemy.inspecting_until > args.state.tick_count

    # Rejoin the circuit at whichever waypoint is closest, rather than the one
    # it was originally heading for. Without this the enemy would often turn
    # around and walk all the way back across the stage, which reads as broken.
    enemy.patrol_index = nearest_waypoint_index enemy
    enemy.mode         = :patrolling
  end

  # Steps the enemy one frame toward (x, depth). Returns true on arrival.
  #
  # The direction vector is normalized before scaling by speed, so the enemy
  # covers the same ground per frame on diagonals as on straight runs -- the
  # same reason the player has a DIAGONAL_FACTOR.
  #
  # A wrinkle specific to this game: x is in pixels and depth is in world units,
  # so this vector mixes two scales. That is fine for a patrol authored by eye,
  # but it means "speed" is not one consistent real-world quantity. If the
  # movement ever needs to feel precisely even, normalize depth into
  # pixel-equivalents first.
  def self.move_toward enemy, target_x, target_depth
    dx = target_x - enemy.x
    dd = target_depth - enemy.depth

    distance = Math.sqrt((dx * dx) + (dd * dd))

    # Must exceed ENEMY_SPEED, or the enemy oversteps every frame and orbits
    # the point forever instead of arriving.
    return true if distance <= Config::ENEMY_ARRIVE_DISTANCE

    enemy.x     += (dx / distance) * Config::ENEMY_SPEED
    enemy.depth  = World.clamp_depth(enemy.depth + ((dd / distance) * Config::ENEMY_SPEED))

    false
  end

  def self.nearest_waypoint_index enemy
    best_index    = 0
    best_distance = nil

    Config::ENEMY_PATROL_POINTS.each_with_index do |point, index|
      dx = point[0] - enemy.x
      dd = point[1] - enemy.depth
      distance = (dx * dx) + (dd * dd)   # squared is enough for comparison

      if best_distance.nil? || distance < best_distance
        best_distance = distance
        best_index    = index
      end
    end

    best_index
  end

  def self.check_contact args
    player = args.state.player

    return if Player.recovering? args
    return unless World.overlap? player, args.state.enemy

    # Losing the effect is a single assignment: the item's visibility and the
    # seam's visibility are both derived from this one flag, so there is nothing
    # else to reset. The item reappears and the seam vanishes on the same tick.
    player.carrying = false
    player.recovering_until = args.state.tick_count + Config::RECOVERY_TICKS
  end
end
