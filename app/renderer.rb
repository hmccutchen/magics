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
      { entity: args.state.player, color: Player.color(args) },
      { entity: args.state.enemy,  color: Config::COLOR_ENEMY }
    ]

    # Each module owns the rule for whether it is on screen; the renderer just
    # asks. Keeps game rules out of the drawing code.
    list << { entity: args.state.item, color: Config::COLOR_ITEM } if Item.visible? args
    list << { entity: args.state.seam, color: Config::COLOR_SEAM } if Seam.visible? args

    if args.state.rock
      list << { entity: args.state.rock, color: Config::COLOR_ROCK, lift: Rock.lift(args) }
    end

    list
  end

  def self.push args, drawable
    rect = World.screen_rect drawable[:entity], (drawable[:lift] || 0)

    args.outputs.sprites << Scene.solid(
      rect[:x], rect[:y], rect[:w], rect[:h], drawable[:color]
    )
  end
end
