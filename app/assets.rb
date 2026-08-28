# Assets
#
# Maps a sprite name and a fidelity tier to real files and their geometry.
#
# The two tiers of an asset are hand-authored and may differ in canvas size,
# proportions, frame count and foot placement -- myth is a DISTORTED version of
# the truth, not merely a coarser one, so a mythologised creature may be the
# wrong shape entirely. Geometry therefore belongs beside each file rather than
# in Config, which keeps only values tuned by feel.
module Assets
  FALLBACK_TIER = :myth

  # Declare a tier only once its art exists. An undeclared tier falls back to
  # myth, which is what lets regions and puzzles be built before the truth art
  # is authored -- a resolved region simply does not change appearance yet.
  # A descriptor names its files one of two ways:
  #
  #   frames: N  -- a numbered cycle, frame_000.png .. frame_(N-1).png
  #   files: []  -- an explicit list, for art that is not a numbered cycle
  #
  # The push poses need the second: they are single held frames named by
  # compass direction, not an animation.
  ASSETS = {
    player_walk: {
      myth: {
        dir: 'sprites/player/myth',
        frames: 8,
        canvas_w: 40,
        canvas_h: 40,
        figure_h: 26,   # visible figure height within the canvas
        foot_pad: 7     # transparent rows below the feet
      }
    }
  }

  # The push poses share a canvas, figure height and foot padding, so they are
  # declared from one shape rather than seven copies of the same four numbers.
  #
  # figure_h is 26 for all of them even though south-east measures 25 -- the
  # walk frames vary the same way and use a single value, because a per-file
  # figure height would resize the character by a pixel as he turned.
  PUSH_POSE_FILES = {
    player_push_north:      'north.png',
    player_push_north_east: 'north-east.png',
    player_push_east:       'east.png',
    player_push_south_east: 'south-east.png',
    player_push_south:      'south.png',
    player_push_west:       'west.png',
    player_push_north_west: 'north-west.png'
  }

  PUSH_POSE_FILES.each do |name, file|
    ASSETS[name] = {
      myth: {
        dir: 'sprites/player/myth',
        files: [file],
        canvas_w: 32,
        canvas_h: 32,
        figure_h: 26,
        foot_pad: 3
      }
    }
  end

  # The owl. Two facings only -- it turns to look at the traveller, and he is
  # beside it rather than above or below it, so east and west are the poses
  # that ever get asked for. The other six directions are drawn and sitting in
  # the same folders; switching one on is a row here, not new code.
  #
  # Flight is a two-frame wingbeat built from files in DIFFERENT folders, which
  # is why `dir` stops at the tier and the folder is part of each filename.
  # Order matters: wings down, then wings up.
  #
  # One figure_h and one foot_pad across all four, not per file. The figures
  # actually measure 39 to 45 tall with 2 to 5 rows below them, but a per-file
  # value would make the owl grow and bob every time it flapped -- the same
  # reason the push poses share one height. 40 is the perched body; the wings
  # are allowed to extend past it.
  OWL_POSES = {
    owl_perched_east: ['idle/east.png'],
    owl_perched_west: ['idle/west.png'],
    owl_flying_east:  ['flying/east.png', 'flapping-wings/east.png'],
    owl_flying_west:  ['flying/west.png', 'flapping-wings/west.png']
  }

  OWL_POSES.each do |name, files|
    ASSETS[name] = {
      myth: {
        dir: 'sprites/owl/myth',
        files: files,
        canvas_w: 48,
        canvas_h: 48,
        figure_h: 40,
        foot_pad: 4,

        # An owl, not a person. This is the number to tune if it reads wrong
        # against the traveller.
        height_px: Config::OWL_HEIGHT_PX
      }
    }
  end

  # Zero-padded by hand rather than with format/rjust: this runs in mruby, which
  # has already silently returned nil from a method MRI accepted. Stdlib
  # coverage is verified, not assumed.
  def self.frame_paths dir, count
    (0...count).map do |index|
      padded = index.to_s
      padded = "0#{padded}" while padded.length < 3
      "#{dir}/frame_#{padded}.png"
    end
  end

  # Paths are built once at load rather than per frame, to avoid allocating
  # strings at 60fps.
  TABLE = {}
  ASSETS.each do |name, tiers|
    TABLE[name] = {}

    tiers.each do |tier, descriptor|
      paths = if descriptor[:files]
                descriptor[:files].map { |file| "#{descriptor[:dir]}/#{file}" }
              else
                frame_paths descriptor[:dir], descriptor[:frames]
              end

      TABLE[name][tier] = descriptor.merge({ paths: paths })
    end
  end

  @warned = {}

  def self.descriptor name, tier
    tiers = TABLE[name]
    raise "Unknown sprite: #{name}" unless tiers
    return tiers[tier] if tiers[tier]

    fallback = tiers[FALLBACK_TIER]
    raise "Sprite #{name} declares no #{FALLBACK_TIER} tier to fall back to" unless fallback

    warn_missing name, tier
    fallback
  end

  # Logged once per sprite/tier pair so an unauthored tier is visible in the
  # log without spamming it 60 times a second.
  def self.warn_missing name, tier
    key = "#{name}/#{tier}"
    return if @warned[key]

    @warned[key] = true
    puts "[Assets] #{name} has no #{tier} tier; falling back to #{FALLBACK_TIER}"
  end

  # `progress` is a normalised 0.0..1.0 position through the animation cycle.
  # The caller never learns how many frames a tier has, which is what makes
  # cadence identical across tiers with differing frame counts.
  def self.frame_path name, tier, progress
    paths = descriptor(name, tier)[:paths]

    index = (progress * paths.length).to_i
    index = 0 if index < 0
    index = paths.length - 1 if index >= paths.length

    paths[index]
  end

  def self.foot_pad_ratio name, tier
    found = descriptor name, tier
    found[:foot_pad].to_f / found[:canvas_h]
  end

  # Drawn canvas size at full scale, derived so the FIGURE lands at
  # Config::CHARACTER_HEIGHT_PX regardless of how the tier was authored.
  # Drawn canvas size at full scale, derived so the FIGURE lands at the
  # descriptor's target height regardless of how the tier was authored.
  #
  # `height_px` is per asset because not everything in this world is
  # person-sized. It defaults to CHARACTER_HEIGHT_PX, so anything that does not
  # say otherwise -- the player and every pose he holds -- is unaffected.
  # Without it an owl would be drawn ninety pixels tall and stand eye to eye
  # with the traveller.
  def self.draw_size name, tier
    found  = descriptor name, tier
    target = found[:height_px] || Config::CHARACTER_HEIGHT_PX
    factor = target.to_f / found[:figure_h]

    [found[:canvas_w] * factor, found[:canvas_h] * factor]
  end
end
