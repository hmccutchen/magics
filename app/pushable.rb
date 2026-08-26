# Pushable
#
# An object the player moves by walking into it. There is no pick-up and no
# button: contact plus movement is the whole verb.
#
# HOW IT MOVES -- the simplest thing that works, deliberately:
#
# While the player's footprint overlaps a pushable, the pushable is displaced
# by the player's own movement for that frame, scaled by PUSH_FACTOR. Copying
# the player's delta rather than running the object at its own speed means the
# two can never separate or interpenetrate while pushing, so no collision
# response is needed anywhere -- and this codebase has none yet.
#
# The cost of that shortcut is at the world edges. When a pushable clamps
# against the stage boundary the player keeps walking and visibly overlaps it.
# Fixing that means blocking the player, which is real collision response and a
# larger change than this step is for.
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

  def self.update args
    defaults args

    player = args.state.player

    # Recomputed every frame rather than latched, so the pose drops the moment
    # contact or movement stops. Player owns the flag because Player.drawable
    # is what reads it.
    player.pushing = false
    return unless player.moving

    args.state.pushables.each do |pushable|
      slide args, player, pushable
    end
  end

  def self.slide args, player, pushable
    return unless World.overlap? player, pushable

    player.pushing = true

    pushable.x = World.clamp_x(
      pushable.x + (player.moved_x * Config::PUSH_FACTOR),
      pushable.fw,
      pushable.depth
    )

    pushable.depth = World.clamp_depth(
      pushable.depth + (player.moved_depth * Config::PUSH_FACTOR)
    )
  end
end
