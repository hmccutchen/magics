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
# next reload the entities we own are dropped and rebuilt from current defaults.
#
# We clear only our own keys rather than calling $gtk.reset, so this stays a
# narrow, predictable action rather than an engine-wide restart.
module GameState
  VERSION = 8

  # Every args.state key that holds an entity built from Config defaults.
  OWNED_KEYS = [:player, :item, :seam, :enemy, :rock]

  def self.ensure_current! args
    # Whether the level is being played or has been completed. Deliberately
    # separate from player.carrying: "has the item's effect" and "the level is
    # over" are orthogonal, and collapsing them into one flag would mean the
    # win state could be undone by an enemy touch.
    args.state.mode ||= :playing

    return if args.state.schema_version == VERSION

    clear_entities args
    args.state.schema_version = VERSION

    log_reset args
  end

  # Puts the level back to its opening position. Entities are dropped rather
  # than individually reset, so they rebuild from Config defaults -- one code
  # path for "new game" and "restart", with nothing to forget to zero out.
  def self.restart! args
    clear_entities args
    args.state.mode = :playing
  end

  def self.clear_entities args
    args.state.player = nil
    args.state.item   = nil
    args.state.seam   = nil
    args.state.enemy  = nil
    args.state.rock   = nil
  end

  def self.log_reset args
    return unless args.state.tick_count > 0

    puts "[GameState] schema v#{VERSION}: rebuilt #{OWNED_KEYS.join ', '}"
  end
end
