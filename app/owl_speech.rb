# OwlSpeech
#
# What the owl says, and when.
#
# PLACEHOLDER TEXT. This slice exists to prove the trigger and display
# mechanism, not to write the owl. One line, deliberately -- more triggers
# arrive in the next step, and the real writing pass comes after both.
#
# --- How this stays decoupled -----------------------------------------------
#
# Nothing in this game emits events. Pattern, Seams, Regions and Creature are
# all polled state. So rather than have them announce things to the owl, the
# owl READS their existing public predicates every tick, remembers what it saw
# last tick, and fires on the change.
#
# That means this file depends on them and NOTHING depends on this file.
# Delete owl_speech.rb and the rest of the game runs unchanged: no callbacks to
# unregister, no other module holding a reference, no system checking whether
# the owl has spoken before it will let the player proceed. The owl reacts to
# the world; the world does not know it is there.
#
# It also cannot gate anything. A trigger only ever chooses a line to display.
# Every pattern in this game is solvable by someone who never hears a word of
# this.
module OwlSpeech
  # Lines are keyed by a STABLE ID and referred to by that id everywhere else.
  # Trigger code names `:fool_reaches`, never the sentence, so the text can be
  # rewritten -- and, later, tracked across repeat firings -- without touching
  # a single trigger.
  #
  # `once` is the firing policy: true means it is heard at most once a
  # playthrough, false means it may recur. Recurrence is the interesting case,
  # since a handful of these lines are meant to repeat verbatim and land
  # differently depending on what the player has lived through by then.
  LINES = {
    fool_reaches: {
      text: 'A fool reaches for goals no one has yet reached.',
      once: false
    }
  }

  # Which line a trigger produces. A table rather than a case statement so a
  # new trigger is a row, and so the id -> line mapping is one thing to read.
  TRIGGERS = {
    region_entered_unresolved: :fool_reaches
  }

  def self.update args
    # Expiry runs BEFORE the trigger check, so a line ending on the very tick
    # something fires does not swallow the new one.
    expire args

    fired = detect_region_entry args
    speak args, TRIGGERS[fired] if fired
  end

  # --- Triggers -------------------------------------------------------------

  # Fires on the tick the player crosses INTO a region whose truth he has not
  # uncovered yet. Built entirely from Regions' existing public predicates.
  def self.detect_region_entry args
    was = args.state.owl_last_region
    now = Regions.at(args.state.player.x, args.state.player.depth)[:name]

    args.state.owl_last_region = now

    # Standing somewhere is not entering it: on the first frame there is no
    # previous region, and the player has not crossed anything yet.
    return nil if was.nil?
    return nil if now == was

    # The wilds is permanently myth and can never be resolved, so "before it
    # resolves" means nothing there. Crossing the uncovered corridor would
    # otherwise trip this every time.
    return nil if now == Regions::WILDS[:name]

    return nil if Regions.resolved? args, now

    :region_entered_unresolved
  end

  # --- Saying it ------------------------------------------------------------

  def self.speaking? args
    !args.state.owl_line.nil?
  end

  def self.expire args
    return unless speaking? args
    return if args.state.tick_count < args.state.owl_line_until

    args.state.owl_line = nil
  end

  def self.speak args, line_id
    # Ignore rather than interrupt. The owl finishing its thought reads calmer
    # than one talking over itself, and it costs no queue and no interrupt
    # rules. The price is that an occasional better-timed line is dropped.
    return if speaking? args

    line = LINES[line_id]
    return if line[:once] && said?(args, line_id)

    args.state.owl_line       = line_id
    args.state.owl_line_until = args.state.tick_count + Config::OWL_LINE_TICKS
    args.state.owl_said       = said_ids(args) + [line_id]
  end

  # Stored as a list of line ids rather than flags on the lines themselves,
  # the same way Regions stores resolved_regions: hot-reload does NOT reset
  # args.state, and anything held as a field forces a schema bump to retune.
  # Symbols migrate for free.
  #
  # A recurring line is appended EVERY time it fires, so this is already a
  # chronological record of what was said rather than a set of what has been.
  # That is what the next step hangs firing context off.
  def self.said_ids args
    args.state.owl_said ||= []
  end

  def self.said? args, line_id
    said_ids(args).include? line_id
  end

  # --- Drawing --------------------------------------------------------------
  #
  # Text tracks the owl through world space rather than sitting in a fixed
  # corner, because the owl is a thing in the world and its speech should read
  # as coming from it.
  #
  # This draws into args.outputs.labels, a DIFFERENT collection from the
  # sprites everything else uses. Collections layer against each other
  # regardless of push order, so labels always land on top of every sprite --
  # the same property that made splitting the backdrop across two collections
  # a bug, and exactly what is wanted for speech. Nothing can occlude it, so
  # the render order of this call does not matter.

  def self.render args
    return unless speaking? args

    owl = args.state.owl
    return unless owl

    text = LINES[args.state.owl_line][:text]
    rect = World.place owl.x, owl.depth, owl.w, owl.h, owl.lift

    # calcstringbox returns [width, height] for the string as it will actually
    # be drawn, which is the only honest way to know where its edges land.
    width = args.gtk.calcstringbox(text, size_px: Config::OWL_SPEECH_SIZE_PX)[0]

    args.outputs.labels << {
      x: label_x(rect[:x] + (rect[:w] / 2.0), width),
      y: rect[:y] + rect[:h] + Config::OWL_SPEECH_RISE_PX,
      text: text,
      size_px: Config::OWL_SPEECH_SIZE_PX,
      alignment_enum: 1,   # 1 = centred on x, so the text sits over the owl
      **Scene.rgb(Config::COLOR_OWL_SPEECH)
    }
  end

  # Keeps the text on stage when the owl is near an edge: the line slides
  # along the bird rather than running off the side. Pure arithmetic, split
  # out from render so it can be checked without an engine.
  def self.label_x centre_x, text_width
    half = text_width / 2.0
    low  = Config::OWL_SPEECH_MARGIN + half
    high = Config::SCREEN_W - Config::OWL_SPEECH_MARGIN - half

    # A line too wide for the screen has no satisfying position, so it is
    # centred and allowed to overhang evenly rather than clamped to nonsense.
    return Config::SCREEN_W / 2.0 if low > high

    centre_x.clamp low, high
  end

  # A trigger naming a line that does not exist would silently never speak,
  # which looks like a broken trigger rather than a typo. Refuse to start
  # instead -- the same stance Regions, Seams and Pattern take on their own
  # authored tables. Runs on load, and therefore on every hot-reload of this
  # file, which is when the tables are most likely to be mid-edit.
  def self.assert_triggers_name_real_lines!
    TRIGGERS.each do |trigger, line_id|
      next if LINES.key? line_id

      raise "Trigger #{trigger} names line #{line_id}, which is not in LINES"
    end
  end

  assert_triggers_name_real_lines!
end
