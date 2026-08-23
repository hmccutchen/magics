# Player
#
# Movement only, for now. No jumping and no gravity -- the player walks on a
# flat plane, so the only two things that change are x and depth.
module Player
  # Creates the player entity the first time through and then leaves it alone.
  #
  # Note the `||= args.state.new_entity`: args.state auto-creates TOP-level
  # keys, but reading an unset key gives you nil rather than a nested entity, so
  # `args.state.player.x ||= 0` raises NoMethodError on nil. Nested state has to
  # be declared. new_entity also tags the entity with a name, which shows up in
  # exception dumps and the console.
  #
  # Because hot-reload does NOT reset args.state, this ||= runs once per state
  # reset rather than per file save -- which is what lets you retune the
  # movement constants below and watch them take effect without losing your
  # position on the map.
  def self.defaults args
    args.state.player ||= args.state.new_entity(:player) do |player|
      player.x     = Config::SCREEN_W / 2
      player.depth = Config::DEPTH_FAR / 2
      player.w     = Config::PLAYER_W
      player.h     = Config::PLAYER_H
      player.fw    = Config::PLAYER_FW
      player.fd    = Config::PLAYER_FD

      # The single source of truth for "does the player have the item's
      # effect right now". The item's visibility and the seam's visibility are
      # both DERIVED from this rather than tracked separately, so they cannot
      # drift out of sync. Step 6 (enemy contact) will flip this back to false.
      player.carrying = false

      # Tick at which the recovery window after an enemy hit expires. Compared
      # against tick_count, so 0 means "not recovering".
      player.recovering_until = 0

      # Last direction the player moved, used to aim the throw. Persists while
      # standing still, so you can stop, turn, and throw. Starts facing right.
      player.facing_x     = 1.0
      player.facing_depth = 0.0
    end
  end

  def self.update args
    defaults args
    move args
  end

  # True while the player is immune following an enemy hit.
  def self.recovering? args
    args.state.player.recovering_until > args.state.tick_count
  end

  # Blinks between the normal and hit colors while recovering, so the immunity
  # window is legible without needing a HUD element.
  def self.color args
    return Config::COLOR_PLAYER unless recovering? args

    phase = (args.state.tick_count / Config::RECOVERY_BLINK_RATE).to_i
    phase.even? ? Config::COLOR_PLAYER_HIT : Config::COLOR_PLAYER
  end

  def self.move args
    player = args.state.player

    # left_right and up_down are DragonRuby conveniences that collapse arrow
    # keys, WASD, and the controller d-pad/stick into a single -1, 0, or 1.
    # up_down returns +1 for up, which we map to "further into the scene".
    dx = args.inputs.left_right
    dd = args.inputs.up_down

    return if dx.zero? && dd.zero?

    # Without this, holding two directions moves you ~41% faster diagonally.
    factor = (dx.zero? || dd.zero?) ? 1.0 : Config::DIAGONAL_FACTOR

    player.facing_x     = dx
    player.facing_depth = dd

    player.depth = World.clamp_depth(
      player.depth + (dd * Config::PLAYER_SPEED_DEPTH * factor)
    )

    # Clamped after depth so the bound reflects the width at the NEW depth.
    player.x = World.clamp_x(
      player.x + (dx * Config::PLAYER_SPEED_X * factor),
      player.w,
      player.depth
    )
  end
end
