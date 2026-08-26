require 'app/config.rb'
require 'app/game_state.rb'
require 'app/world.rb'
require 'app/regions.rb'
require 'app/assets.rb'
require 'app/scene.rb'
require 'app/player.rb'
require 'app/seams.rb'
require 'app/creature.rb'
require 'app/rock.rb'
require 'app/renderer.rb'

module Main
  def tick args
    # Must run before anything reads an entity, so that a shape change made
    # while the game is running rebuilds them instead of crashing on nil.
    GameState.ensure_current! args

    # Restart is checked BEFORE update, deliberately. GameState.restart! drops
    # the entities to nil so they rebuild from defaults; if that happened later
    # in the frame, the render pass would read nil entities and crash. Running
    # it here means the very next line recreates everything in the same tick.
    GameState.restart! args if args.inputs.keyboard.key_down.r

    update args
    render args
  end

  def update args
    Player.update args
    Seams.update args
    Creature.update args

    # After Creature, so an object landing this tick redirects the creature
    # starting next tick rather than being overwritten by its wander step.
    Rock.update args
  end

  def render args
    Scene.render args
    Renderer.draw args
  end
end
