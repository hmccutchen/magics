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
      # Set while resolving a move; drives which sprite set is drawn and
      # slows the next frame's step.
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

  # Which held pose to draw at :rumour, keyed the same way PUSH_POSES is:
  # STAND_POSES[depth facing][horizontal facing] -> sprite name.
  #
  # Unlike the push table there is nothing mirrored here. The 2-bit set has a
  # real south-west, so every direction is its own drawing and none of them
  # need flipping.
  STAND_POSES = {
     1 => {
      -1 => :player_stand_north_west,
       0 => :player_stand_north,
       1 => :player_stand_north_east
    },
     0 => {
      -1 => :player_stand_west,
       0 => :player_stand_south,
       1 => :player_stand_east
    },
    -1 => {
      -1 => :player_stand_south_west,
       0 => :player_stand_south,
       1 => :player_stand_south_east
    }
  }

  # Where the TRAVELLER is on the fidelity ladder, which is not the same
  # question as where the ground under him is.
  #
  # Everything else in the world takes its tier from the region it stands in,
  # because fidelity is a property of place. He is the exception: what he is
  # drawn as follows him, so crossing out of a resolved region does not undo
  # what he has understood. He starts at 2-bit and steps up to his 8-bit self
  # the first time he completes a pattern.
  #
  # Above that first rung, place governs him again exactly as it did before,
  # so a resolved region still steps him to :truth when that art exists.
  def self.tier args
    return :rumour unless stepped_up? args

    player = args.state.player

    Regions.tier_at args, player.x, player.depth
  end

  # Keyed on the seam being REVEALED rather than on `Pattern.complete?`,
  # which is recomputed live from where the blocks currently sit and goes
  # false again if he shoves one back out. Noticing something is not the sort
  # of thing that can be taken back, so the step up has to hang off the
  # permanent fact, not the reversible one.
  def self.stepped_up? args
    Seams.revealed_names(args).any?
  end

  # Everything the renderer needs to draw the player this frame. Carries a
  # sprite NAME and a normalised cycle position rather than a file path, which
  # is what makes cadence independent of frame count: a 4-frame myth cycle and
  # an 8-frame truth cycle cover the same ground.
  #
  # It DOES carry a tier, unlike every other drawable, for the reason given on
  # `tier` above -- he is the one thing whose fidelity is not read off the
  # ground he is standing on.
  def self.drawable args
    tier = tier args

    return push_drawable args, tier if args.state.player.pushing
    return stand_drawable args, tier if tier == :rumour

    {
      entity: args.state.player,
      sprite: :player_walk,
      progress: cycle_progress(args),
      flip: args.state.player.heading_x < 0,
      tier: tier
    }
  end

  # The 2-bit traveller, standing or walking. One held pose either way: there
  # is no 2-bit walk cycle, and at this fidelity there is not supposed to be.
  #
  # facing_x and facing_depth persist while he stands still, so he keeps
  # looking the way he last walked rather than snapping back to a default.
  # Both are read through to_i because they are seeded as Floats and set from
  # input as Integers, and a Hash keyed on 1 does not answer to 1.0.
  def self.stand_drawable args, tier
    player = args.state.player

    row  = STAND_POSES[player.facing_depth.to_i] || STAND_POSES[0]
    pose = row[player.facing_x.to_i] || :player_stand_south

    {
      entity: player,
      sprite: pose,
      tier: tier
    }
  end

  # The push pose is a single held frame, not a cycle -- he braces and stays
  # braced while the object slides -- so no progress is passed.
  #
  # Direction comes from facing, which is set from this frame's input. Falls
  # back to the south pose rather than raising if facing is ever a value the
  # table has no row for.
  #
  # The push poses declare no :rumour art, so while he is 2-bit this asks for
  # a tier that does not exist and Assets hands back the 8-bit pose, logging
  # the gap once. That is the intended state, not a bug: pushing is held at
  # 8-bit until the 2-bit push art is drawn, at which point declaring it in
  # Assets is the whole change.
  def self.push_drawable args, tier
    player = args.state.player

    row  = PUSH_POSES[player.facing_depth.to_i] || PUSH_POSES[0]
    pose = row[player.facing_x.to_i] || [:player_push_south, false]

    {
      entity: player,
      sprite: pose[0],
      flip: pose[1],
      progress: cycle_progress(args, Config::PUSH_CYCLE_DISTANCE),
      tier: tier
    }
  end

  # Vertical rise and fall while pushing, in screen pixels.
  #
  # Driven by walk_distance rather than a timer, for the same reason the walk
  # cycle is: cadence then follows ground speed automatically, so a slower
  # diagonal push bobs slower too and there is no foot-sliding to tune away.
  #
  # abs(sin) rather than sin, so the body only ever rises off the ground line
  # and returns to it -- one hump per footfall, never dipping below his feet.
  #
  # Scaled by depth so the bob shrinks along with him as he walks away. The
  # thrown rock's arc deliberately does NOT do this, because its height reads
  # as distance travelled rather than as part of the figure.
  # Normalised 0.0..1.0 through an animation cycle, from ground covered rather
  # than from a timer -- which is what locks the feet to walking speed, so a
  # slower push animates slower with nothing to tune. `cycle_distance` is the
  # ground one full cycle covers, and differs between walking and pushing.
  def self.cycle_progress args, cycle_distance = Config::WALK_CYCLE_DISTANCE
    player = args.state.player
    return 0.0 unless player.moving

    (player.walk_distance % cycle_distance) / cycle_distance
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
      player.pushing = false
      return
    end

    # Read before clearing. Whether this step is a push is only known once the
    # move is resolved below, so the slowdown necessarily uses last frame's
    # answer. Contact persists across frames, so the one-frame lag is not
    # visible -- and the alternative, resolving twice per frame, is a lot of
    # machinery to remove something nobody can see.
    slowed = player.pushing
    player.pushing = false

    # Captured before the move so the distance accumulated reflects what
    # actually happened. Walking into a clamp covers no ground, and therefore
    # correctly does not advance the animation.
    start_x     = player.x
    start_depth = player.depth

    # Without this, holding two directions moves you ~41% faster diagonally.
    factor = (dx.zero? || dd.zero?) ? 1.0 : Config::DIAGONAL_FACTOR

    # Shifting something has weight to it. The pushable copies this slowed
    # delta, so the object slows down with him rather than pulling ahead.
    factor *= Config::PUSH_SPEED_FACTOR if slowed

    player.facing_x     = dx
    player.facing_depth = dd
    player.heading_x    = dx unless dx.zero?

    candidate_depth = World.clamp_depth(
      player.depth + (dd * Config::PLAYER_SPEED_DEPTH * factor)
    )

    # Clamped after depth, so the bound reflects the width at the NEW depth,
    # and against the FOOTPRINT width rather than the drawn width -- the sprite
    # canvas is mostly transparent padding, so clamping by `w` would stop the
    # player a canvas-half-width short of each edge for no visible reason.
    candidate_x = World.clamp_x(
      player.x + (dx * Config::PLAYER_SPEED_X * factor),
      player.fw,
      candidate_depth
    )

    # The world gets the last word: a step that would put the player inside
    # something they cannot shift does not happen.
    resolved     = Pushable.resolve args, player, candidate_x, candidate_depth
    player.x     = resolved[0]
    player.depth = resolved[1]

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
    moved_x     = player.x - start_x
    moved_depth = player.depth - start_depth
    moved       = Math.sqrt((moved_x * moved_x) + (moved_depth * moved_depth))

    # Wrapped to a COMMON MULTIPLE of every cycle distance, not to the walk
    # cycle alone. Wrapping at the walk cycle would land mid-stride for the
    # push cycle, which is a different length, and skip a frame every time it
    # came round. The product is the cheapest common multiple to state and
    # needs no explanation beyond this one; if a third cycle length ever
    # appears, it belongs in here too.
    cycle = Config::WALK_CYCLE_DISTANCE * Config::PUSH_CYCLE_DISTANCE
    player.walk_distance = (player.walk_distance + moved) % cycle
  end

end
