require 'app/config.rb'
require 'app/game_state.rb'
require 'app/world.rb'
require 'app/scene.rb'
require 'app/player.rb'
require 'app/item.rb'
require 'app/seam.rb'
require 'app/enemy.rb'
require 'app/rock.rb'
require 'app/renderer.rb'
require 'app/completion.rb'

module Main
  def tick args
    # Must run before anything reads an entity, so that a shape change made
    # while the game is running rebuilds them instead of crashing on nil.
    GameState.ensure_current! args

    # Restart is checked BEFORE update, deliberately. GameState.restart! drops
    # the entities to nil so they rebuild from defaults; if that happened later
    # in the frame, the render pass would read nil entities and crash. Running
    # it here means the very next line recreates everything in the same tick.
    Completion.check_restart args if args.state.mode == :complete

    update args unless args.state.mode == :complete
    render args
  end

  # The whole simulation for one frame. Skipped entirely once the level is
  # complete, which is what "the game stops" means here -- the enemy stops
  # patrolling, the rock stops flying, and nothing can undo the win.
  def update args
    Player.update args
    Item.update args

    # Before Enemy, so that being caught on the same tick as a pickup wins.
    Seam.update args
    Enemy.update args

    # After Enemy, so a rock landing this tick redirects the enemy starting
    # next tick rather than being overwritten by its patrol step.
    Rock.update args
  end

  def render args
    Scene.render args
    Renderer.draw args

    Completion.render args if args.state.mode == :complete
  end
end
