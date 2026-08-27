require 'app/config.rb'
require 'app/game_state.rb'
require 'app/world.rb'
require 'app/regions.rb'
require 'app/assets.rb'
require 'app/scene.rb'
require 'app/player.rb'
require 'app/seams.rb'
require 'app/throwables.rb'
require 'app/creature.rb'
require 'app/owl.rb'
require 'app/owl_speech.rb'
require 'app/pushable.rb'
require 'app/pattern.rb'
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
    # Before Player, so the pushables exist by the time a move is resolved
    # against them.
    Pushable.update args

    Player.update args

    # After Player, so a socket filled by this frame's push is recognised now
    # rather than a frame later.
    Pattern.update args

    Seams.update args
    Creature.update args

    # After Player, so the owl follows where he IS this frame rather than
    # trailing a frame behind him.
    Owl.update args

    # After Creature and Pushable, so an object landing this tick takes effect
    # starting next tick rather than being overwritten by their own steps.
    Rock.update args

    # Genuinely last. A line fires against the world as it stands at the END
    # of the frame, so a region resolved this tick is already resolved when
    # the owl looks at it. It reads existing state; nothing reads it back.
    OwlSpeech.update args
  end

  def render args
    Scene.render args

    # Between the two: sockets are markings on the floor, so they sit above the
    # backdrop and below everything that stands on it.
    Pattern.render args

    Renderer.draw args

    # Draws into args.outputs.labels, which layers above every sprite whatever
    # the order here, so this sits last simply because it is drawn last.
    OwlSpeech.render args
  end
end
