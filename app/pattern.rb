# Pattern
#
# The puzzle the push verb exists for, and the only thing that reveals a seam.
#
# A socket is a mark in the ground that something belongs in. It starts hidden
# under an object that does NOT belong in it, which is the whole shape of the
# thing: you shift the wrong object off, the mark underneath comes to light,
# and only then does it read that a second object across the clearing is the
# one it matches.
#
#   push the wrong object off  ->  the mark is revealed
#   push the right object in   ->  the pattern completes, the seam appears
#
# The two steps do not need enforcing in code. Objects already block each
# other, so the right one physically cannot reach the socket until the wrong
# one has been moved -- the order falls out of the collision rules rather than
# being policed by a state machine.
#
# Nothing here fails. A wrong push just means the pattern is not complete yet,
# and every part of it can be undone by pushing things back out again. Only
# the seam being revealed is permanent, because noticing something is not the
# sort of thing that can be taken back.
module Pattern
  # Authored placements, beside the code that reads them, matching Seams and
  # Pushable. `covered_by` and `filled_by` index into Pushable::PUSHABLES.
  #
  # One socket, in one region. Story-doc open question 5 -- how many pattern
  # moments this world holds, and whether they share a rhythm -- is unanswered,
  # so this is shaped to hold more without any of them being invented yet.
  SOCKETS = [
    {
      region: :far_stand,
      x: 400,
      depth: 200.0,
      covered_by: 0,   # sits on the socket at the start, and does not fit it
      filled_by: 1     # the one that does
    }
  ]

  def self.update args
    regions.each do |region_name|
      next if Seams.revealed? args, region_name
      next unless complete? args, region_name

      Seams.reveal! args, region_name
    end
  end

  def self.regions
    SOCKETS.map { |socket| socket[:region] }.uniq
  end

  # A region's seam appears once every socket in it is filled. With one socket
  # that is the same as "the socket is filled", but it is written this way so
  # that a second socket in the same region is data rather than new code.
  def self.complete? args, region_name
    SOCKETS.each do |socket|
      next unless socket[:region] == region_name
      return false unless filled?(args, socket)
    end

    true
  end

  # Is a given object sitting in this socket? A box rather than a radius,
  # because x is pixels and depth is world units and a single distance across
  # the two would be tighter on one axis than the other without saying so.
  def self.seated? args, socket, index
    pushable = args.state.pushables[index]
    return false unless pushable

    (pushable.x - socket[:x]).abs <= Config::SOCKET_TOLERANCE_X &&
      (pushable.depth - socket[:depth]).abs <= Config::SOCKET_TOLERANCE_DEPTH
  end

  def self.filled? args, socket
    seated? args, socket, socket[:filled_by]
  end

  # Hidden until whatever was sitting on it has been shifted off.
  def self.revealed? args, socket
    !seated?(args, socket, socket[:covered_by])
  end

  # --- Drawing -------------------------------------------------------------
  #
  # A socket is a marking on the ground, so it draws between the backdrop and
  # the entities rather than among them -- it is part of the floor, and nothing
  # should ever sort in front of or behind it.
  #
  # Bounds follow Regions.screen_bounds: depth maps to screen y, and x passes
  # straight through, because the projection has no horizontal foreshortening.

  def self.render args
    SOCKETS.each do |socket|
      next unless revealed? args, socket

      outline args, socket
    end
  end

  def self.outline args, socket
    near = World.ground_y socket[:depth] - Config::SOCKET_TOLERANCE_DEPTH
    far  = World.ground_y socket[:depth] + Config::SOCKET_TOLERANCE_DEPTH

    bounds = {
      x: socket[:x] - Config::SOCKET_TOLERANCE_X,
      y: near,
      w: Config::SOCKET_TOLERANCE_X * 2,
      h: far - near
    }

    color = filled?(args, socket) ? Config::COLOR_SOCKET_FILLED : Config::COLOR_SOCKET

    Scene.outline args, bounds, color
  end

  # A socket nobody can fill, or one whose two objects are the same, would be a
  # puzzle that silently cannot be solved. Refuse to start instead -- the same
  # stance Regions takes on overlapping bounds.
  def self.assert_solvable!
    SOCKETS.each do |socket|
      if socket[:covered_by] == socket[:filled_by]
        raise "Socket in #{socket[:region]} is covered and filled by the same object"
      end

      [socket[:covered_by], socket[:filled_by]].each do |index|
        next if index >= 0 && index < Pushable::PUSHABLES.length

        raise "Socket in #{socket[:region]} refers to pushable #{index}, which does not exist"
      end
    end
  end

  # A socket outside the region it names would reveal a seam somewhere the
  # player is standing nowhere near.
  def self.assert_inside_declared_region!
    SOCKETS.each do |socket|
      actual = Regions.at(socket[:x], socket[:depth])[:name]
      next if actual == socket[:region]

      raise "Socket declares region #{socket[:region]} but sits in #{actual}"
    end
  end

  assert_solvable!
  assert_inside_declared_region!
end
