# Regions
#
# The world is divided into authored areas. Each is either myth (the
# dramatised version the traveller tells himself) or truth (what actually
# happened). Repairing a seam resolves one region.
#
# Definitions are constants; resolution is runtime state. That split is
# deliberate: DragonRuby's hot-reload re-evaluates code but does NOT reset
# args.state, and changing the shape of a stored entity mid-session has already
# blanked this game's screen once. Because the only thing stored here is a list
# of symbols, region bounds can be retuned live with no state migration.
#
# Bounds use the same convention as World.footprint: `depth` is the second
# axis, NOT a screen coordinate. Membership is plain arithmetic rather than
# DragonRuby's Geometry mixin, so this module loads unchanged in plain Ruby and
# can be checked outside the engine.
module Regions
  # Anywhere not inside a defined region. Permanently myth, so that regions can
  # be authored incrementally without the renderer hitting a nil tier.
  WILDS = { name: :wilds, x: 0, depth: 0, w: Config::SCREEN_W, h: Config::DEPTH_FAR }

  # Regions may not overlap -- see assert_no_overlap! at the bottom of this file.
  # The corridor between x=520 and x=760 is deliberately left uncovered so the
  # wilds fallback is exercised by the running game, not only by the harness.
  REGIONS = [
    { name: :fern_hollow,   x: 0,   depth: 0,   w: 520,  h: 160 },
    { name: :east_clearing, x: 760, depth: 0,   w: 520,  h: 160 },
    { name: :far_stand,     x: 0,   depth: 160, w: 1280, h: 140 }
  ]

  # Half-open on both axes: the low edge belongs to this region, the high edge
  # belongs to the next. Without that rule a point on a shared border would
  # match two regions and lookup would depend on declaration order.
  def self.contains? region, x, depth
    x >= region[:x] && x < region[:x] + region[:w] &&
      depth >= region[:depth] && depth < region[:depth] + region[:h]
  end

  def self.at x, depth
    REGIONS.each do |region|
      return region if contains? region, x, depth
    end

    WILDS
  end

  def self.resolved_names args
    args.state.resolved_regions ||= []
  end

  def self.resolved? args, name
    resolved_names(args).include? name
  end

  # Reassigns rather than mutating in place, so nothing depends on how
  # args.state hands back a stored array.
  def self.resolve! args, name
    return if name == WILDS[:name]
    return if resolved? args, name

    args.state.resolved_regions = resolved_names(args) + [name]
  end

  def self.tier_at args, x, depth
    resolved?(args, at(x, depth)[:name]) ? :truth : :myth
  end

  # A region rect maps to a plain screen rectangle: the depth->y mapping is
  # linear and there is no horizontal foreshortening, so no trapezoid
  # projection is needed. If foreshortening is ever added, this is the only
  # function that changes.
  #
  # Named to differ from World.screen_rect, which converts a single entity and
  # is a different operation.
  def self.screen_bounds region
    near = World.ground_y region[:depth]
    far  = World.ground_y region[:depth] + region[:h]

    { x: region[:x], y: near, w: region[:w], h: far - near }
  end

  def self.rects_overlap? a, b
    a[:x] < b[:x] + b[:w] && a[:x] + a[:w] > b[:x] &&
      a[:depth] < b[:depth] + b[:h] && a[:depth] + a[:h] > b[:depth]
  end

  def self.overlapping
    pairs = []

    REGIONS.each_with_index do |a, i|
      REGIONS.each_with_index do |b, j|
        next if j <= i

        pairs << [a[:name], b[:name]] if rects_overlap? a, b
      end
    end

    pairs
  end

  # Overlapping bounds make lookup order-dependent, which surfaces as "the tier
  # is wrong sometimes" -- miserable to diagnose. Refuse to start instead.
  # Runs on load, and therefore again on every hot-reload of this file.
  def self.assert_no_overlap!
    bad = overlapping
    return if bad.empty?

    raise "Regions overlap: #{bad.map { |pair| pair.join(' & ') }.join(', ')}"
  end

  assert_no_overlap!
end
