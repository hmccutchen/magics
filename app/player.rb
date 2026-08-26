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

      # Ground actually covered this frame, per axis. Published so Pushable can
      # displace an object by exactly what the player moved, which is what
      # keeps the two from separating without any collision response. Reset
      # every frame, so it is never stale.
      player.moved_x     = 0.0
      player.moved_depth = 0.0

      # Set by Pushable each frame; drives which sprite set is drawn.
      player.pushing = false
    end
  end

  def self.update args
    defaults args
    move args
  end

  # Which push pose to draw, keyed by the direction being walked:
  # PUSH_POSES[depth input][horizontal input] -> [sprite name, mirrored?].
  #
  # Integer keys rather than an [x, depth] array key, and a lookup table rather
  # than a built-up string, because this runs every frame and the codebase
  # already avoids allocating at 60fps.
  #
  # +1 depth is INTO the scene, matching args.inputs.up_down.
  #
  # There is no south-west art yet, so it mirrors south-east -- the same trick
  # the walk cycle uses to serve both horizontal directions from one set. Add
  # a south-west.png, declare it in Assets, and this one entry replaces it.
  PUSH_POSES = {
     1 => {
      -1 => [:player_push_north_west, false],
       0 => [:player_push_north,      false],
       1 => [:player_push_north_east, false]
    },
     0 => {
      -1 => [:player_push_west,  false],
       0 => [:player_push_south, false],
       1 => [:player_push_east,  false]
    },
    -1 => {
      -1 => [:player_push_south_east, true],
       0 => [:player_push_south,      false],
       1 => [:player_push_south_east, false]
    }
  }

  # Everything the renderer needs to draw the player this frame. Deliberately
  # carries a sprite NAME and a normalised cycle position, never a file path
  # and never a tier -- the renderer resolves both from where the player is
  # standing. This is also what makes cadence independent of frame count: a
  # 4-frame myth cycle and an 8-frame truth cycle cover the same ground.
  def self.drawable args
    return push_drawable args if args.state.player.pushing

    {
      entity: args.state.player,
      sprite: :player_walk,
      progress: cycle_progress(args),
      flip: args.state.player.heading_x < 0
    }
  end

  # The push pose is a single held frame, not a cycle -- he braces and stays
  # braced while the object slides -- so no progress is passed.
  #
  # Direction comes from facing, which is set from this frame's input. Falls
  # back to the south pose rather than raising if facing is ever a value the
  # table has no row for.
  def self.push_drawable args
    player = args.state.player

    row  = PUSH_POSES[player.facing_depth] || PUSH_POSES[0]
    pose = row[player.facing_x] || [:player_push_south, false]

    {
      entity: player,
      sprite: pose[0],
      flip: pose[1]
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

    unless player.moving
      player.moved_x     = 0.0
      player.moved_depth = 0.0
      return
    end

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
  # Same mixed-unit caveat as the creature's circuit: x is pixels and depth is world
  # units, so this magnitude is not one consistent real-world quantity. It is
  # driving an animation cadence, not physics, so eyeballed is fine.
  def self.accumulate_distance player, start_x, start_depth
    player.moved_x     = player.x - start_x
    player.moved_depth = player.depth - start_depth

    moved_x     = player.moved_x
    moved_depth = player.moved_depth
    moved       = Math.sqrt((moved_x * moved_x) + (moved_depth * moved_depth))

    cycle = Config::WALK_CYCLE_DISTANCE
    player.walk_distance = (player.walk_distance + moved) % cycle
  end

end
