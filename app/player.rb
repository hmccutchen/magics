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
      player.fw    = Config::PLAYER_FW
      player.fd    = Config::PLAYER_FD

      # The single source of truth for "does the player have the item's
      # effect right now". The item's visibility is DERIVED from this rather
      # than tracked separately, so the two cannot drift out of sync. Enemy
      # contact flips it back to false.
      #
      # Seam visibility no longer rides on this flag: revealing a seam is a
      # one-way fact about the world, not a carried effect.
      player.carrying = false

      # Tick at which the recovery window after an enemy hit expires. Compared
      # against tick_count, so 0 means "not recovering".
      player.recovering_until = 0

      # Last direction the player moved, used to aim the throw. Persists while
      # standing still, so you can stop, turn, and throw. Starts facing right.
      player.facing_x     = 1.0
      player.facing_depth = 0.0

      # Which way the sprite faces: -1 left, 1 right. Kept SEPARATE from
      # facing_x because that one is the throw's aim vector and legitimately
      # goes to 0 when walking straight along the depth axis. The sprite must
      # never face "nowhere", so this only updates on actual horizontal input.
      player.heading_x = 1

      # Ground covered so far, wrapped to one full animation cycle. Driving the
      # walk cycle off distance rather than a timer keeps the feet locked to
      # ground speed: the cadence follows the speed automatically, so diagonal
      # movement (which is slower) animates slower too, and there is no
      # foot-sliding to tune away.
      player.walk_distance = 0.0
      player.moving        = false
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

  # Fades in and out while recovering, so the immunity window stays legible
  # without a HUD element. The gray-box swapped colours; a sprite blinks by
  # dropping alpha instead.
  def self.alpha args
    return 255 unless recovering? args

    phase = (args.state.tick_count / Config::RECOVERY_BLINK_RATE).to_i
    phase.even? ? Config::RECOVERY_BLINK_ALPHA : 255
  end

  # Everything the renderer needs to draw the player this frame. Deliberately
  # carries a sprite NAME and a normalised cycle position, never a file path
  # and never a tier -- the renderer resolves both from where the player is
  # standing. This is also what makes cadence independent of frame count: a
  # 4-frame myth cycle and an 8-frame truth cycle cover the same ground.
  def self.drawable args
    {
      entity: args.state.player,
      sprite: :player_walk,
      progress: cycle_progress(args),
      flip: args.state.player.heading_x < 0,
      alpha: alpha(args)
    }
  end

  # Position through the walk cycle, 0.0 to 1.0. Standing still reports 0.0
  # rather than holding its last value, so an idle player returns to the
  # neutral frame instead of freezing mid-stride.
  def self.cycle_progress args
    player = args.state.player
    return 0.0 unless player.moving

    player.walk_distance / Config::WALK_CYCLE_DISTANCE
  end

  def self.move args
    player = args.state.player

    # left_right and up_down are DragonRuby conveniences that collapse arrow
    # keys, WASD, and the controller d-pad/stick into a single -1, 0, or 1.
    # up_down returns +1 for up, which we map to "further into the scene".
    dx = args.inputs.left_right
    dd = args.inputs.up_down

    player.moving = !(dx.zero? && dd.zero?)
    return unless player.moving

    # Captured before the move so the distance accumulated reflects what
    # actually happened. Walking into a clamp covers no ground, and therefore
    # correctly does not advance the animation.
    start_x     = player.x
    start_depth = player.depth

    # Without this, holding two directions moves you ~41% faster diagonally.
    factor = (dx.zero? || dd.zero?) ? 1.0 : Config::DIAGONAL_FACTOR

    player.facing_x     = dx
    player.facing_depth = dd
    player.heading_x    = dx unless dx.zero?

    player.depth = World.clamp_depth(
      player.depth + (dd * Config::PLAYER_SPEED_DEPTH * factor)
    )

    # Clamped after depth, so the bound reflects the width at the NEW depth,
    # and against the FOOTPRINT width rather than the drawn width -- the sprite
    # canvas is mostly transparent padding, so clamping by `w` would stop the
    # player a canvas-half-width short of each edge for no visible reason.
    player.x = World.clamp_x(
      player.x + (dx * Config::PLAYER_SPEED_X * factor),
      player.fw,
      player.depth
    )

    accumulate_distance player, start_x, start_depth
  end

  # Adds the ground actually covered this frame, wrapped to one cycle so the
  # accumulator stays bounded over a long session instead of drifting into
  # float imprecision.
  #
  # Same mixed-unit caveat as the enemy's patrol: x is pixels and depth is world
  # units, so this magnitude is not one consistent real-world quantity. It is
  # driving an animation cadence, not physics, so eyeballed is fine.
  def self.accumulate_distance player, start_x, start_depth
    moved_x     = player.x - start_x
    moved_depth = player.depth - start_depth
    moved       = Math.sqrt((moved_x * moved_x) + (moved_depth * moved_depth))

    cycle = Config::WALK_CYCLE_DISTANCE
    player.walk_distance = (player.walk_distance + moved) % cycle
  end

end
