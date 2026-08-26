# Throwables
#
# What the player can throw, and what a landing does to whatever is near it.
#
# Two kinds for now, told apart by colour until there is art -- one draws
# things toward where it lands, the other sends them away. That difference is
# the whole point of having more than one: the same verb either gathers or
# scatters, so a spot you need cleared and a spot you need filled are the same
# problem approached from opposite ends.
#
# Only `effect` is game logic. The colour that stands in for each kind lives in
# Config with the rest of the gray-box palette, so replacing these with real
# art touches rendering and nothing else.
#
# Both the creature and pushable objects respond. A pushable drifting toward a
# noise is a deliberate choice, not physics: it makes these objects read as
# faintly alive, which is the direction the world is already going.
module Throwables
  KINDS = [
    { name: :lure,  effect: :attract },
    { name: :scare, effect: :repel }
  ]

  def self.at index
    KINDS[index % KINDS.length]
  end

  def self.selected args
    at(args.state.throwable_index || 0)
  end

  # Unit vector pointing from the landing spot toward the thing reacting, and
  # the distance it should travel. Attracting flips the direction, so both
  # effects share one piece of arithmetic rather than two near-copies.
  #
  # A landing exactly on top of something leaves no direction, so the caller
  # supplies a fallback rather than this inventing one.
  def self.direction effect, from_x, from_depth, to_x, to_depth, fallback
    dx = to_x - from_x
    dd = to_depth - from_depth

    distance = Math.sqrt((dx * dx) + (dd * dd))
    dx, dd   = fallback if distance <= 0.001
    distance = 1.0 if distance <= 0.001

    sign = effect == :attract ? -1.0 : 1.0

    [(dx / distance) * sign, (dd / distance) * sign]
  end
end
