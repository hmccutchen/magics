# Assets
#
# Maps a sprite name and a fidelity tier to real files and their geometry.
#
# The two tiers of an asset are hand-authored and may differ in canvas size,
# proportions, frame count and foot placement -- myth is a DISTORTED version of
# the truth, not merely a coarser one, so a mythologised creature may be the
# wrong shape entirely. Geometry therefore belongs beside each file rather than
# in Config, which keeps only values tuned by feel.
# The tiers form a LADDER, coarsest first:
#
#   :rumour  2-bit. Barely enough information to be a story yet.
#   :myth    8-bit. The traveller's own dramatised account of what happened.
#   :truth   16-bit. What actually happened.
#
# The world climbs it by place, a region at a time (`Regions.tier_at`). The
# TRAVELLER climbs it by progress instead, and carries the result everywhere
# he goes -- see `Player.tier`, which is the one deliberate exception to
# fidelity being a property of place.
module Assets
  FALLBACK_TIER = :myth

  # Declare a tier only once its art exists. An undeclared tier falls back to
  # myth, which is what lets regions and puzzles be built before the truth art
  # is authored -- a resolved region simply does not change appearance yet.
  # It is also how the push poses are held back at 8-bit while the rest of the
  # traveller is 2-bit: they simply declare no :rumour tier.
  # A descriptor names its files one of two ways:
  #
  #   frames: N  -- a numbered cycle, frame_000.png .. frame_(N-1).png
  #   files: []  -- an explicit list, for art that is not a numbered cycle
  #
  # The push poses need the second: they are single held frames named by
  # compass direction, not an animation.
  # Names a numbered cycle sitting in its own folder, RELATIVE to a
  # descriptor's dir -- which is what lets one asset pull frames from a folder
  # the others do not use. `frame_paths` below does the same job for a cycle
  # that lives directly in `dir`.
  #
  # Padded by hand for the same reason frame_paths is: this runs in mruby,
  # whose stdlib coverage is verified rather than assumed.
  def self.numbered_files dir, count
    (0...count).map do |index|
      padded = index.to_s
      padded = "0#{padded}" while padded.length < 3
      "#{dir}/frame_#{padded}.png"
    end
  end

  ASSETS = {
    player_walk: {
      # The 2-bit walk, DERIVED from the myth cycle rather than drawn
      # separately: same eight frames, same poses, same cadence, reduced to
      # four colours and half the spatial resolution. Because it comes from
      # the same art, its geometry is identical to the myth cycle's below --
      # not copied, measured -- so the traveller does not move or resize when
      # he resolves. Only his fidelity changes, which is the whole point.
      rumour: {
        dir: 'sprites/player/rumour/walk',
        frames: 8,
        canvas_w: 40,
        canvas_h: 40,
        figure_h: 26,
        foot_pad: 7
      },

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

  # The push walk: a full NINE-frame stride per direction, in its own folder
  # per direction.
  #
  # It used to be two frames -- feet planted, then mid-stride -- alternating.
  # That was enough to stop him sliding the crate while standing still, but
  # two poses is not a walk: his feet arrive and leave without ever passing
  # through anything, so the legs read as static. Nine frames is an actual
  # stride.
  #
  # frame_000 is the old planted pose, so a push that begins from standing
  # still starts on the pose he was already holding rather than snapping into
  # the middle of a stride. Same reasoning that leads the owl's wingbeat with
  # the pose it was gliding on.
  #
  # Canvas is 48 here where the old push art was 32 -- these were generated on
  # the larger canvas and there is no reason to crop them back, since geometry
  # is per descriptor and figure_h normalises the drawn size anyway. 26 and 11
  # are measured off the frames.
  #
  # Still no south-west: the base set never had one, and PUSH_POSES in
  # player.rb mirrors south-east, which now mirrors all nine frames so
  # south-west strides like everything else.
  PUSH_FRAMES = 9

  PUSH_POSE_DIRS = {
    player_push_north:      'north',
    player_push_north_east: 'north-east',
    player_push_east:       'east',
    player_push_south_east: 'south-east',
    player_push_south:      'south',
    player_push_west:       'west',
    player_push_north_west: 'north-west'
  }

  # Both tiers, from the same nine frames -- the rumour set is derived from
  # the myth set by tools/build_rumour.py, so the geometry below is shared
  # because it is measured off art that came from the same drawing.
  #
  # Pushing was deliberately held back at 8-bit while the low tier had no push
  # art. It has one now, and being the last thing that did not step down made
  # him revert to full colour the moment he leaned on a crate, which read as a
  # rendering bug rather than as a tier.
  PUSH_POSE_DIRS.each do |name, direction|
    geometry = {
      files: numbered_files("push/#{direction}", PUSH_FRAMES),
      canvas_w: 48,
      canvas_h: 48,
      figure_h: 26,
      foot_pad: 11
    }

    ASSETS[name] = {
      rumour: geometry.merge({ dir: 'sprites/player/rumour' }),
      myth:   geometry.merge({ dir: 'sprites/player/myth' })
    }
  end

  # The owl. Two facings only -- it turns to look at the traveller, and he is
  # beside it rather than above or below it, so east and west are the poses
  # that ever get asked for. The other six directions are drawn and sitting in
  # the same folders; switching one on is a row here, not new code.
  #
  # Three poses, because the owl is in three visibly different situations:
  # perched on something, gliding above the traveller, and beating its wings.
  # Flight is the only animated one: a full nine-frame stroke, wings sweeping
  # down below the body and back up above it, returning to where it started so
  # the cycle loops.
  #
  # The wingbeat lives in its own folder per facing and is NUMBERED, unlike
  # every other owl pose, which is a single held frame named by compass
  # direction. `dir` still stops at the tier and the folder is part of each
  # filename -- that is what lets one descriptor pull frames from a folder the
  # others do not use.
  #
  # frame_000 is the pose the owl was already holding (the old `flying` art),
  # so a beat that begins from a glide starts on the pose already on screen
  # rather than snapping into the middle of a stroke. Same reasoning as the
  # push poses leading with the planted frame.
  #
  # foot_pad is PER POSE, because these canvases are registered differently:
  # the soaring bird sits 8 rows off the bottom where the perched one sits 4.
  # That is safe here only because the poses never share an animation cycle --
  # a soaring owl does not flap, so the two are never alternated and the
  # difference cannot show up as a jitter. It is corrected per pose instead,
  # so each one lands at the height it is supposed to.
  #
  # figure_h is ONE value across all of them, unlike foot_pad. It sets the
  # scale, so varying it would resize the bird as it changed pose. 40 is the
  # perched body; the soaring figure is shorter and much wider, and is
  # supposed to look that way.
  WINGBEAT_FRAMES = 9

  OWL_POSES = {
    owl_perched_east: { files: ['idle/east.png'],    foot_pad: 4 },
    owl_perched_west: { files: ['idle/west.png'],    foot_pad: 4 },
    owl_soaring_east: { files: ['soaring/east.png'], foot_pad: 8 },
    owl_soaring_west: { files: ['soaring/west.png'], foot_pad: 8 },

    # foot_pad 6 rather than the old 3, measured off the new frames: the bird
    # RISES AND FALLS through the stroke (the generated cycle moves the whole
    # body, not just the wings), so its feet sit higher in the canvas on
    # average than the old two-frame art did. One value for all nine on
    # purpose -- a per-frame pad would cancel that bob out, which is the part
    # that makes the flight look worked for. It also sits much closer to the
    # soaring pose's 8, so the bird no longer steps up when a glide breaks
    # into a beat.
    owl_flying_east: {
      files: numbered_files('wingbeat/east', WINGBEAT_FRAMES),
      foot_pad: 6
    },
    owl_flying_west: {
      files: numbered_files('wingbeat/west', WINGBEAT_FRAMES),
      foot_pad: 6
    }
  }

  OWL_POSES.each do |name, pose|
    ASSETS[name] = {
      myth: {
        dir: 'sprites/owl/myth',
        files: pose[:files],
        canvas_w: 48,
        canvas_h: 48,
        figure_h: 40,
        foot_pad: pose[:foot_pad],

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
