# GameState
#
# Guards against stale state after a hot-reload.
#
# Hot-reload re-evaluates your code but deliberately does NOT reset args.state
# -- that is what lets you retune a constant and see it live without losing your
# position. The cost is that entity defaults, which are written as
# `||= new_entity`, only run when the entity is first created. If you add a
# field to an entity while the game is running, every existing entity keeps the
# OLD shape, and the new code reads nil off it. That is not a subtle bug: it
# raises every tick and the screen goes blank, because DragonRuby aborts the
# tick on an exception and nothing gets drawn.
#
# So: bump VERSION whenever an entity gains, loses, or renames a field. On the
# next reload the level restarts -- entities rebuilt from current defaults, and
# progress cleared, since progress made under the old shape is not progress this
# code knows how to honour.
#
# We clear only our own keys rather than calling $gtk.reset, so this stays a
# narrow, predictable action rather than an engine-wide restart.
module GameState
  VERSION = 19

  # Every args.state key that holds an entity built from Config defaults.
  OWNED_KEYS = [:player, :seams, :pushables, :creature, :rock]

  def self.ensure_current! args
    return if args.state.schema_version == VERSION

    # A shape change means the world we are holding is not the world this code
    # expects, so start the level over rather than rebuilding entities into
    # progress they were never part of.
    restart! args
    args.state.schema_version = VERSION

    log_reset args
  end

  # Puts the level back to its opening position. Entities are dropped rather
  # than individually reset, so they rebuild from Config defaults -- one code
  # path for "new game", "restart" and "schema changed", with nothing to forget
  # to zero out.
  def self.restart! args
    clear_entities args
    args.state.resolved_regions = []
    args.state.revealed_seams   = []
    args.state.charging_since   = nil
    args.state.throwable_index  = 0
  end

  def self.clear_entities args
    args.state.player    = nil
    args.state.seams     = nil
    args.state.pushables = nil
    args.state.creature  = nil
    args.state.rock      = nil
  end

  def self.log_reset args
    return unless args.state.tick_count > 0

    puts "[GameState] schema v#{VERSION}: rebuilt #{OWNED_KEYS.join ', '}"
  end
end
