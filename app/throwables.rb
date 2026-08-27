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
# The creature is what responds. Inert objects do not: they are moved by being
# pushed, which is a separate verb, and giving the throw a way to move them too
# would leave pushing with nothing of its own to do.
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

  # Colour is how the two are told apart, so a kind without one is a kind the
  # player cannot identify. Cheaper to refuse at load than to find out when the
  # renderer indexes past the end and blanks the screen mid-frame.
  def self.assert_every_kind_has_a_colour!
    return if Config::COLOR_THROWABLE.length == KINDS.length

    raise "COLOR_THROWABLE has #{Config::COLOR_THROWABLE.length} entries for #{KINDS.length} throwable kinds"
  end

  assert_every_kind_has_a_colour!
end
