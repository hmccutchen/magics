# OwlSpeech
#
# What the owl says, and when.
#
# PLACEHOLDER TEXT. This slice exists to prove the trigger and display
# mechanism, not to write the owl. The real writing pass comes later; the
# only real line here is the draft one from the story doc.
#
# --- What makes it speak ----------------------------------------------------
#
# Two things, and deliberately only two:
#
#   1. The player CLICKS it. He is asking, so it answers.
#   2. The STORY has a hint to offer. Today there is exactly one such beat,
#      and it comes straight from the story doc: "once a seam is revealed,
#      the owl hints at how to activate it."
#
# It does NOT chatter at the world. The owl is "the part of a person that
# already knows the truth" -- something spoken to, or something that speaks
# when it has cause, not an ambient commentary track narrating your footsteps.
#
# --- How this stays decoupled -----------------------------------------------
#
# Nothing in this game emits events. Pattern, Seams, Regions and Creature are
# all polled state. So rather than have them announce things to the owl, the
# owl READS their existing public predicates every tick and fires on the
# change.
#
# That means this file depends on them and NOTHING depends on this file.
# Delete owl_speech.rb and the rest of the game runs unchanged: no callbacks
# to unregister, no other module holding a reference, no system checking
# whether the owl has spoken before it will let the player proceed. The owl
# reacts to the world; the world does not know it is there.
#
# It also cannot gate anything. A trigger only ever chooses a line to display.
# Every pattern in this game stays solvable by someone who never hears a word
# of this, which is the story doc's position too -- the owl hints, and the
# player's capacity to understand it is what changes, not the world's rules.
module OwlSpeech
  # Lines are keyed by a STABLE ID and referred to by that id everywhere else.
  # Trigger code names `:fool_reaches`, never the sentence, so the text can be
  # rewritten -- and, later, tracked across repeat firings -- without touching
  # a single trigger.
  #
  # `once` is the firing policy: true means it is heard at most once a
  # playthrough, false means it may recur. Recurrence is the interesting case.
  # Per the story doc, a small number of these lines are meant to repeat
  # VERBATIM and land differently depending on what the player has lived
  # through by then -- the words do not change, the reader does.
  LINES = {
    # The draft line from the story doc, whose stated job is to hint toward
    # activating a seam. Repeatable on purpose: it is the example the doc
    # gives of a line that should reread as plainly true later.
    fool_reaches: {
      text: 'A fool reaches for goals no one has yet reached.',
      once: false
    },

    # PLACEHOLDER, and marked as such in the text itself so it cannot be
    # mistaken for writing. Stands in for whatever the owl says when asked
    # with nothing pending.
    nothing_pending: {
      text: '(placeholder) The owl looks at you, and waits.',
      once: false
    }
  }

  # Hints the STORY offers unprompted. A table rather than a case statement so
  # a new beat is a row, and so the trigger -> line mapping is one thing to
  # read. One entry today, because one beat is actually built.
  STORY_TRIGGERS = {
    seam_revealed: :fool_reaches
  }

  # What a click produces when there is nothing pending to hint about.
  IDLE_LINE = :nothing_pending

  def self.update args
    # Expiry runs BEFORE anything else, so a line ending on the very tick
    # something fires does not swallow the new one.
    expire args

    # A click takes precedence over the world offering: the player asked, so
    # answer him rather than saying something he did not ask for.
    return if try_click args

    try_story_hint args
  end

  # --- The player asking ----------------------------------------------------

  def self.try_click args
    return false unless clicked_owl? args

    speak args, click_line(args)
  end

  # Hit testing happens in SCREEN space, which is the one place in this game
  # that is correct. Everything else collides on the ground plane in
  # (x, depth) because two things at different depths can overlap on screen
  # while being most of the stage apart. A mouse click is not in the world at
  # all, though -- it is a point on the picture -- so the honest target is the
  # rectangle the owl is DRAWN in, lift included, since the bird the player is
  # aiming at is the one up in the air.
  def self.clicked_owl? args
    click = args.inputs.mouse.click
    return false unless click

    owl = args.state.owl
    return false unless owl

    click.inside_rect? hit_rect(owl)
  end

  def self.hit_rect owl
    rect = World.place owl.x, owl.depth, owl.w, owl.h, owl.lift
    pad  = Config::OWL_CLICK_PADDING_PX

    {
      x: rect[:x] - pad,
      y: rect[:y] - pad,
      w: rect[:w] + (pad * 2),
      h: rect[:h] + (pad * 2)
    }
  end

  # Asked while a seam is sitting revealed and unactivated, the owl gives the
  # hint the story doc says it owes. Otherwise it has nothing to offer, and
  # says so -- it does not invent a hint to fill the silence.
  def self.click_line args
    return STORY_TRIGGERS[:seam_revealed] if seam_awaiting_activation? args

    IDLE_LINE
  end

  # A seam that has been revealed but whose region has not resolved. Built
  # from the two modules' existing predicates -- neither learns the owl exists.
  def self.seam_awaiting_activation? args
    Seams.revealed_names(args).any? do |region|
      !Regions.resolved?(args, region)
    end
  end

  # --- The story offering ---------------------------------------------------

  def self.try_story_hint args
    seen = args.state.owl_seen_seams ||= []
    now  = Seams.revealed_names args

    return false if (now - seen).empty?

    # The edge is consumed only once the line has actually LANDED. If the owl
    # happened to be mid-sentence, the hint is not lost -- this simply tries
    # again next tick and arrives the moment it can. A story hint is the one
    # line worth not dropping; an idle remark is not, which is why the click
    # path has no equivalent and is allowed to be ignored.
    return false unless speak args, STORY_TRIGGERS[:seam_revealed]

    args.state.owl_seen_seams = now.dup
    true
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

  # Returns whether the line actually landed, which is what lets a story hint
  # hold its edge open until it does.
  def self.speak args, line_id
    # Ignore rather than interrupt. The owl finishing its thought reads calmer
    # than one talking over itself, and it costs no queue and no interrupt
    # rules.
    return false if speaking? args

    line = LINES[line_id]
    return false if line[:once] && said?(args, line_id)

    args.state.owl_line       = line_id
    args.state.owl_line_until = args.state.tick_count + Config::OWL_LINE_TICKS
    args.state.owl_said       = said_ids(args) + [line_id]

    true
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
  # as coming from it. The story doc's "no UI or dialogue box telling the
  # player so" restraint is the reason this stays a bare line of text.
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
  def self.assert_every_referenced_line_exists!
    (STORY_TRIGGERS.values + [IDLE_LINE]).each do |line_id|
      next if LINES.key? line_id

      raise "Owl speech refers to line #{line_id}, which is not in LINES"
    end
  end

  assert_every_referenced_line_exists!
end
