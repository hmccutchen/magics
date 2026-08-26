require 'app/config.rb'
require 'app/game_state.rb'
require 'app/world.rb'
require 'app/regions.rb'
require 'app/assets.rb'
require 'app/scene.rb'
require 'app/player.rb'
require 'app/item.rb'
require 'app/seams.rb'
require 'app/enemy.rb'
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
    Item.update args

    # Before Enemy, so that a seam activated on the same tick as a pickup still
    # resolves its region rather than being pre-empted by an enemy touch.
    Seams.update args
    Enemy.update args

    # After Enemy, so a rock landing this tick redirects the enemy starting
    # next tick rather than being overwritten by its patrol step.
    Rock.update args
  end

  def render args
    Scene.render args
    Renderer.draw args
  end
end
