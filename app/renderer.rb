# Renderer
#
# Draws every depth-aware entity in the correct back-to-front order.
#
# DragonRuby has no z-index. Within a given output collection, things are drawn
# in the order they were pushed -- later pushes land on top. Collections
# themselves are also layered relative to each other, so splitting drawables
# across `sprites` and `lines` would silently break depth sorting no matter how
# carefully we sorted.
#
# The whole game therefore draws into ONE collection, args.outputs.sprites,
# with Scene pushing the backdrop first. We build the entity list, sort it
# farthest-first, and append it after.
module Renderer
  def self.draw args
    entities(args)
      .sort_by { |drawable| -drawable[:entity].depth }  # far -> near
      .each { |drawable| push args, drawable }
  end

  # Everything that lives on the ground plane and must participate in depth
  # sorting. Colors live here rather than on the entities themselves so that
  # args.state stays game logic and does not accumulate presentation data.
  def self.entities args
    list = [
      Player.drawable(args),
      { entity: args.state.creature, color: Config::COLOR_CREATURE },

      # The owl is airborne: `lift` raises where it is DRAWN without touching
      # its depth, so it still sorts by the ground beneath it.
      Owl.drawable(args)
    ]

    # Each module owns the rule for whether it is on screen; the renderer just
    # asks. Keeps game rules out of the drawing code.
    Seams.visible(args).each do |seam|
      list << { entity: seam, color: Config::COLOR_SEAM }
    end

    args.state.pushables.each_with_index do |pushable, index|
      list << {
        entity: pushable,
        color: Config::COLOR_PUSHABLE[index],
        offset_x: pushable.lag_x,
        offset_depth: pushable.lag_depth
      }
    end

    if args.state.rock
      # Coloured by what it is, not by being a rock -- the two kinds are told
      # apart by colour until there is art for them.
      list << {
        entity: args.state.rock,
        color: Config::COLOR_THROWABLE[args.state.rock.kind_index],
        lift: Rock.lift(args)
      }
    end

    list
  end

  def self.push args, drawable
    if drawable[:sprite]
      push_sprite args, drawable
    else
      push_solid args, drawable
    end
  end

  # Resolves the drawable's sprite name to a file through its tier, which is
  # normally the tier of the region its ground position falls in. Entities do
  # not learn their own tier: fidelity is a property of place, and place is
  # the renderer's business.
  #
  # The traveller is the single exception -- what he is drawn as follows him
  # rather than the ground -- so a drawable may override the answer by
  # carrying its own :tier. See `Player.tier`.
  def self.push_sprite args, drawable
    name   = drawable[:sprite]
    tier   = tier_for args, drawable
    rect   = sprite_rect args, drawable

    args.outputs.sprites << Scene.image(
      rect[:x],
      rect[:y],
      rect[:w],
      rect[:h],
      Assets.frame_path(name, tier, drawable[:progress] || 0.0),
      drawable[:flip],
      drawable[:alpha] || 255
    )
  end

  # Where a sprite drawable actually lands on screen.
  #
  # Split out of push_sprite so that anything needing to know where an entity
  # was DRAWN -- the owl's click target, the line of text above its head --
  # asks the renderer the same question rather than recomputing it and
  # drifting out of step the first time the art changes.
  # The one place both the tier rule and the override live, so push_sprite and
  # sprite_rect cannot disagree about what fidelity a thing was drawn at.
  def self.tier_for args, drawable
    return drawable[:tier] if drawable[:tier]

    entity = drawable[:entity]

    Regions.tier_at args, entity.x, entity.depth
  end

  def self.sprite_rect args, drawable
    entity = drawable[:entity]
    name   = drawable[:sprite]
    tier   = tier_for args, drawable

    width, height = Assets.draw_size name, tier
    rect = World.place entity.x, entity.depth, width, height, (drawable[:lift] || 0)

    # Push the sprite DOWN so its feet, rather than its canvas bottom, land on
    # the ground plane. Scales with the drawn size, so the character stays
    # planted at every depth instead of drifting upward as it grows.
    rect[:y] -= rect[:h] * Assets.foot_pad_ratio(name, tier)

    rect
  end

  # `offset_*` nudge only where the entity is DRAWN, never where it is. Depth
  # sorting still uses the true depth, so a trailing object cannot swap places
  # with something it is level with.
  def self.push_solid args, drawable
    entity = drawable[:entity]

    rect = World.place(
      entity.x + (drawable[:offset_x] || 0),
      entity.depth + (drawable[:offset_depth] || 0),
      entity.w,
      entity.h,
      drawable[:lift] || 0
    )

    args.outputs.sprites << Scene.solid(
      rect[:x], rect[:y], rect[:w], rect[:h], drawable[:color]
    )
  end
end
