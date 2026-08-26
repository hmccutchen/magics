# Seams
#
# A gold seam is the one thing that turns a region from myth to truth.
#
# Lifecycle, per the story doc:
#
#   hidden --(pattern completed)--> revealed --(activated)--> repaired
#
# Only part of that is built here.
#
# REVEALING belongs to the pattern-completion loop, which is a later step in
# this slice. Until it lands every seam starts revealed -- temporary
# scaffolding, so the fidelity system stays reachable in the meantime.
#
# ACTIVATION is still "walk into it", and is a PLACEHOLDER rather than a
# decision: open question 4 in the story doc -- what activating a seam changes
# on screen -- is unresolved, and the owl, which is supposed to hint at how to
# activate, does not exist yet. This is the same check the retired goal object
# used, kept because reveal-then-activate is one designed beat and dropping the
# second half would leave nothing to resolve a region at all.
#
# There is no `repaired` flag. One seam per region means a repaired seam IS a
# resolved region, so Regions.resolved? already answers it -- one fact, stored
# once, rather than a second flag to keep in sync by hand.
module Seams
  # Geometry lives here rather than in Config, matching Regions: Config keeps
  # only values tuned by feel, and these are authored positions that belong
  # beside the assertions that check them.
  #
  # `region` names the region this seam resolves. It is declared rather than
  # derived from the position, so a seam nudged across a boundary while
  # authoring trips the startup assertion below instead of silently resolving
  # a region the player is standing nowhere near.
  #
  # One seam, in one region, on purpose. Story-doc open question 5 (how many
  # pattern moments this world holds) is unanswered, so the table is shaped to
  # hold more without any of them being invented yet.
  SEAMS = [
    { region: :far_stand, x: 1000, depth: 250.0, w: 26, h: 120, fw: 46, fd: 30 }
  ]

  def self.defaults args
    args.state.seams ||= SEAMS.map do |seam|
      args.state.new_entity(:seam) do |entity|
        entity.region = seam[:region]
        entity.x      = seam[:x]
        entity.depth  = seam[:depth]
        entity.w      = seam[:w]
        entity.h      = seam[:h]
        entity.fw     = seam[:fw]
        entity.fd     = seam[:fd]
      end
    end

    # Temporary: revealing a seam is the pattern-completion loop's job, and
    # that has not been built yet. The pickup used to stand in for it; the
    # pickup belonged to the retired adversarial loop and is gone, so until
    # pattern completion lands every seam starts revealed. Delete this call
    # and its method when it does.
    reveal_all! args
  end

  # See the note in `defaults`. Temporary scaffolding, not a mechanic.
  def self.reveal_all! args
    SEAMS.each { |seam| reveal! args, seam[:region] }
  end

  def self.update args
    defaults args

    args.state.seams.each do |seam|
      check_activated args, seam
    end
  end

  # --- Revealed state -------------------------------------------------------
  #
  # Stored as a list of region symbols rather than a flag on each seam entity,
  # for the same reason Regions stores resolved_regions that way: hot-reload
  # re-evaluates code but does NOT reset args.state, so anything held as an
  # entity field forces a schema bump to retune. Symbols migrate for free.

  def self.revealed_names args
    args.state.revealed_seams ||= []
  end

  def self.revealed? args, region_name
    revealed_names(args).include? region_name
  end

  # Reassigns rather than mutating in place, so nothing depends on how
  # args.state hands back a stored array.
  def self.reveal! args, region_name
    return if revealed? args, region_name

    args.state.revealed_seams = revealed_names(args) + [region_name]
  end

  # A repaired seam keeps drawing. The image the story doc is reaching for is
  # kintsugi -- the gold line is what remains once the break is mended, not
  # something that disappears on success.
  def self.visible args
    defaults args

    args.state.seams.select { |seam| revealed? args, seam.region }
  end

  def self.check_activated args, seam
    return unless revealed? args, seam.region
    return unless World.overlap? args.state.player, seam

    Regions.resolve! args, seam.region
  end

  # --- Authoring guards -----------------------------------------------------
  #
  # Both run on load, and therefore again on every hot-reload of this file --
  # which is exactly when a hand-tuned position is most likely to be wrong.

  # Two seams in one region would make "repaired" ambiguous, since repaired is
  # derived from the region rather than tracked per seam.
  def self.assert_one_per_region!
    names = SEAMS.map { |seam| seam[:region] }
    dupes = names.select { |name| names.count(name) > 1 }.uniq
    return if dupes.empty?

    raise "Multiple seams declared for region: #{dupes.join ', '}"
  end

  # A seam sitting outside the region it claims resolves ground somewhere else
  # on the map. Cheap to check, miserable to diagnose by eye.
  def self.assert_inside_declared_region!
    SEAMS.each do |seam|
      actual = Regions.at(seam[:x], seam[:depth])[:name]
      next if actual == seam[:region]

      raise "Seam declares region #{seam[:region]} but sits in #{actual} at (#{seam[:x]}, #{seam[:depth]})"
    end
  end

  assert_one_per_region!
  assert_inside_declared_region!
end
