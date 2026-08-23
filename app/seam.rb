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

  # Reaching a visible seam completes the level.
  #
  # No `visible?` guard is needed for correctness -- the seam is only visible
  # while carrying, and carrying is the same flag -- but checking it makes the
  # rule explicit rather than implied by a coincidence elsewhere.
  def self.check_reached args
    return unless visible? args
    return unless World.overlap? args.state.player, args.state.seam

    args.state.mode = :complete
  end

  def self.visible? args
    args.state.player.carrying
  end
end
