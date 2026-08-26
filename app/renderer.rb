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
      { entity: args.state.enemy, color: Config::COLOR_ENEMY }
    ]

    # Each module owns the rule for whether it is on screen; the renderer just
    # asks. Keeps game rules out of the drawing code.
    list << { entity: args.state.item, color: Config::COLOR_ITEM } if Item.visible? args

    Seams.visible(args).each do |seam|
      list << { entity: seam, color: Config::COLOR_SEAM }
    end

    if args.state.rock
      list << { entity: args.state.rock, color: Config::COLOR_ROCK, lift: Rock.lift(args) }
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

  # Resolves the drawable's sprite name to a file through the tier of the region
  # its ground position falls in. Entities never learn their own tier: fidelity
  # is a property of place, and place is the renderer's business.
  def self.push_sprite args, drawable
    entity = drawable[:entity]
    name   = drawable[:sprite]
    tier   = Regions.tier_at args, entity.x, entity.depth

    width, height = Assets.draw_size name, tier
    rect = World.place entity.x, entity.depth, width, height, (drawable[:lift] || 0)

    # Push the sprite DOWN so its feet, rather than its canvas bottom, land on
    # the ground plane. Scales with the drawn size, so the character stays
    # planted at every depth instead of drifting upward as it grows.
    inset = rect[:h] * Assets.foot_pad_ratio(name, tier)

    args.outputs.sprites << Scene.image(
      rect[:x],
      rect[:y] - inset,
      rect[:w],
      rect[:h],
      Assets.frame_path(name, tier, drawable[:progress] || 0.0),
      drawable[:flip],
      drawable[:alpha] || 255
    )
  end

  def self.push_solid args, drawable
    rect = World.screen_rect drawable[:entity], (drawable[:lift] || 0)

    args.outputs.sprites << Scene.solid(
      rect[:x], rect[:y], rect[:w], rect[:h], drawable[:color]
    )
  end
end
