# Seam
#
# The goal object. Invisible until the player is carrying the item, and
# untouchable while invisible -- reaching it is the win condition in step 6.
#
# Like the item, it holds no visibility flag of its own; it is visible exactly
# when the player is carrying.
module Seam
  def self.defaults args
    args.state.seam ||= args.state.new_entity(:seam) do |seam|
      seam.x     = Config::SEAM_X
      seam.depth = Config::SEAM_DEPTH
      seam.w     = Config::SEAM_W
      seam.h     = Config::SEAM_H
      seam.fw    = Config::SEAM_FW
      seam.fd    = Config::SEAM_FD
    end
  end

  def self.update args
    defaults args
    check_reached args
  end

  # Reaching a visible seam resolves the region the SEAM stands in -- not the
  # region the player stands in, so the outcome does not depend on which side
  # of a boundary the player approached from.
  #
  # No `visible?` guard is needed for correctness -- the seam is only visible
  # while carrying, and carrying is the same flag -- but checking it makes the
  # rule explicit rather than implied by a coincidence elsewhere.
  #
  # Temporary wiring: the real trigger is the pattern-completion loop, which is
  # a later slice. This exercises the fidelity system end to end without having
  # to build the puzzle mechanic first.
  def self.check_reached args
    return unless visible? args
    return unless World.overlap? args.state.player, args.state.seam

    seam = args.state.seam
    Regions.resolve! args, Regions.at(seam.x, seam.depth)[:name]
  end

  def self.visible? args
    args.state.player.carrying
  end
end
