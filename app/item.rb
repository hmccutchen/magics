# Item
#
# The pickup that grants the player the ability to see the seam. Walking into
# it on the ground plane picks it up.
#
# The item has no `collected` flag of its own -- it is visible exactly when the
# player is not carrying it. Deriving visibility from one boolean means there is
# no second flag to forget to reset when the enemy takes the effect away.
module Item
  def self.defaults args
    args.state.item ||= args.state.new_entity(:item) do |item|
      item.x     = Config::ITEM_X
      item.depth = Config::ITEM_DEPTH
      item.w     = Config::ITEM_W
      item.h     = Config::ITEM_H
      item.fw    = Config::ITEM_FW
      item.fd    = Config::ITEM_FD
    end
  end

  def self.update args
    defaults args

    return unless visible? args
    return unless World.overlap? args.state.player, args.state.item

    args.state.player.carrying = true
  end

  def self.visible? args
    !args.state.player.carrying
  end
end
