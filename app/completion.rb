# Completion
#
# The "Level Complete" banner and the restart key.
#
# Nothing here updates the world. When the level is complete the scene is still
# drawn -- frozen exactly as it was at the winning frame -- with this banner on
# top, so the moment stays legible instead of cutting to a blank screen.
module Completion
  TITLE  = 'LEVEL COMPLETE'
  PROMPT = 'press R to play again'

  def self.render args
    banner args
    title args
    prompt args
  end

  def self.banner args
    args.outputs.sprites << Scene.solid(
      0,
      (Config::SCREEN_H / 2) - (Config::BANNER_H / 2),
      Config::SCREEN_W,
      Config::BANNER_H,
      Config::COLOR_BANNER_BG,
      Config::BANNER_ALPHA
    )
  end

  def self.title args
    args.outputs.labels << {
      x: Config::SCREEN_W / 2,
      y: (Config::SCREEN_H / 2) + 34,
      text: TITLE,
      size_px: Config::BANNER_TITLE_PX,
      alignment_enum: 1,           # 0 left, 1 center, 2 right
      **Scene.rgb(Config::COLOR_BANNER)
    }
  end

  def self.prompt args
    args.outputs.labels << {
      x: Config::SCREEN_W / 2,
      y: (Config::SCREEN_H / 2) - 24,
      text: PROMPT,
      size_px: Config::BANNER_PROMPT_PX,
      alignment_enum: 1,
      **Scene.rgb(Config::COLOR_TEXT_DIM)
    }
  end

  def self.check_restart args
    return unless args.inputs.keyboard.key_down.r

    GameState.restart! args
  end
end
