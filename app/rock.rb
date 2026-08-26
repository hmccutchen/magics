# Rock
#
# The thrown object. It is a noise-maker, not a weapon -- it never touches the
# creature and never needs to. Landing is the entire point: a landing close
# enough to startle sends the creature bolting a short way off, which is how
# the player asks it to move out of the way.
#
# Nothing is scored and nothing is harmed. A throw that lands wide of the
# creature simply makes a noise and is ignored.
#
# Lifecycle, tracked by `mode`:
#
#   (none) --hold space--> charging --release--> :flying --> :landed --> (none)
#
# Holding the key winds the throw up: release at once for a toss at your feet,
# hold to THROW_CHARGE_TICKS for a full-strength throw. Distance, time in the
# air and arc height all scale together, because a short toss that hung in the
# air as long as a long one reads as floating.
#
# Only one rock exists at a time. That is the throttle: there is no cooldown
# timer, you simply cannot throw again until the previous rock is gone.
module Rock
  def self.update args
    charge args

    return unless args.state.rock

    case args.state.rock.mode
    when :flying then advance_flight args
    when :landed then advance_linger args
    end
  end

  # Winds a throw up while the key is held and releases it on key-up.
  #
  # `charging_since` is a plain tick number in state rather than a field on an
  # entity, so it survives a hot-reload without a schema migration -- the same
  # reason resolved_regions is a list of symbols.
  def self.charge args
    # A throw is allowed only when no rock is in play, so a wind-up started
    # while one is still in the air is dropped rather than queued.
    if args.state.rock
      args.state.charging_since = nil
      return
    end

    if args.inputs.keyboard.key_down.space
      args.state.charging_since = args.state.tick_count
    elsif args.state.charging_since && args.inputs.keyboard.key_up.space
      spawn args, charge_progress(args)
      args.state.charging_since = nil
    end
  end

  # How wound up the current throw is, 0.0 to 1.0. Zero when nothing is being
  # charged, so a released throw always has a strength to read.
  def self.charge_progress args
    return 0.0 unless args.state.charging_since

    held = args.state.tick_count - args.state.charging_since

    (held.to_f / Config::THROW_CHARGE_TICKS).clamp 0.0, 1.0
  end

  def self.lerp low, high, t
    low + ((high - low) * t)
  end

  def self.spawn args, strength
    player = args.state.player

    reach_x     = lerp Config::THROW_DISTANCE_X_MIN, Config::THROW_DISTANCE_X_MAX, strength
    reach_depth = lerp Config::THROW_DISTANCE_DEPTH_MIN, Config::THROW_DISTANCE_DEPTH_MAX, strength

    # The facing is the player's last movement direction, which may be
    # diagonal. Scaling each axis by its own distance keeps the throw feeling
    # even despite x and depth being different units.
    target_x     = player.x + (player.facing_x * reach_x)
    target_depth = player.depth + (player.facing_depth * reach_depth)

    args.state.rock = args.state.new_entity(:rock) do |rock|
      rock.w  = Config::ROCK_W
      rock.h  = Config::ROCK_H
      rock.fw = Config::ROCK_FW
      rock.fd = Config::ROCK_FD

      rock.origin_x     = player.x
      rock.origin_depth = player.depth

      # Kept inside the stage so a throw at the edge cannot startle the
      # creature toward somewhere it can never reach.
      rock.target_x     = target_x.clamp 0, Config::SCREEN_W
      rock.target_depth = World.clamp_depth target_depth

      rock.x     = rock.origin_x
      rock.depth = rock.origin_depth

      rock.mode        = :flying
      rock.landed_at   = 0
      rock.launched_at = args.state.tick_count

      # Time in the air and arc height are fixed at launch and carried on the
      # rock, so a constant retuned mid-flight cannot warp a throw already
      # under way.
      rock.flight_ticks = lerp Config::THROW_FLIGHT_TICKS_MIN, Config::THROW_FLIGHT_TICKS_MAX, strength
      rock.arc_height   = lerp Config::ROCK_ARC_HEIGHT_MIN, Config::ROCK_ARC_HEIGHT_MAX, strength
    end
  end

  def self.advance_flight args
    rock = args.state.rock

    # Progress through the flight, 0.0 at launch to 1.0 on landing.
    elapsed = args.state.tick_count - rock.launched_at
    t       = (elapsed.to_f / rock.flight_ticks).clamp 0.0, 1.0

    rock.x     = rock.origin_x + ((rock.target_x - rock.origin_x) * t)
    rock.depth = rock.origin_depth + ((rock.target_depth - rock.origin_depth) * t)

    return if t < 1.0

    rock.mode      = :landed
    rock.landed_at = args.state.tick_count

    Creature.startle args, rock.x, rock.depth
  end

  def self.advance_linger args
    rock = args.state.rock
    return if args.state.tick_count - rock.landed_at < Config::ROCK_LINGER_TICKS

    args.state.rock = nil
  end

  # Height above the ground plane, in screen pixels, for drawing only.
  #
  # A parabola peaking at mid-flight: 4t(1-t) is 0 at both ends and 1 at t=0.5.
  # This deliberately does NOT affect the rock's depth -- the rock sorts against
  # other entities by where it is on the ground, not by how high it has been
  # lobbed, which is what keeps it from popping in front of things it is behind.
  def self.lift args
    rock = args.state.rock
    return 0 unless rock && rock.mode == :flying

    elapsed = args.state.tick_count - rock.launched_at
    t       = (elapsed.to_f / rock.flight_ticks).clamp 0.0, 1.0

    rock.arc_height * 4.0 * t * (1.0 - t)
  end
end
