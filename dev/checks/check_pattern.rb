require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/pushable.rb'
require_relative '../../app/seams.rb'
require_relative '../../app/pattern.rb'

# Stand-ins for DragonRuby's args.state and its entities.
class FakePushable
  attr_accessor :x, :depth

  def initialize x, depth
    @x = x
    @depth = depth
  end
end

class FakeState
  attr_accessor :resolved_regions, :revealed_seams, :pushables
end

class FakeArgs
  attr_reader :state

  def initialize
    @state = FakeState.new
    @state.pushables = Pushable::PUSHABLES.map { |p| FakePushable.new p[:x], p[:depth] }
  end
end

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

SOCKET = Pattern::SOCKETS[0]

# Loading pattern.rb runs assert_solvable! and assert_inside_declared_region!,
# so reaching this line is itself the check that the authored socket coheres.
puts 'the authored socket passes its own load-time guards'
check 'a socket is declared', Pattern::SOCKETS.length >= 1, true
check 'socket sits in the region it names',
      Regions.at(SOCKET[:x], SOCKET[:depth])[:name], SOCKET[:region]

puts 'at the start the socket is hidden and empty'
args = FakeArgs.new
check 'covered by the object on top of it', Pattern.revealed?(args, SOCKET), false
check 'not filled',                        Pattern.filled?(args, SOCKET),   false
check 'no seam yet',                       Pattern.complete?(args, SOCKET[:region]), false

puts 'shifting the wrong object off reveals the mark'
args.state.pushables[SOCKET[:covered_by]].x += (Config::SOCKET_TOLERANCE_X * 2) + 1
check 'revealed',        Pattern.revealed?(args, SOCKET), true
check 'still not filled', Pattern.filled?(args, SOCKET),  false
check 'still no seam',   Pattern.complete?(args, SOCKET[:region]), false

puts 'seating the right object completes it'
filler = args.state.pushables[SOCKET[:filled_by]]
filler.x     = SOCKET[:x]
filler.depth = SOCKET[:depth]
check 'filled',   Pattern.filled?(args, SOCKET), true
check 'complete', Pattern.complete?(args, SOCKET[:region]), true

puts 'completing it reveals that region\'s seam, once'
Pattern.update args
check 'seam revealed',        Seams.revealed?(args, SOCKET[:region]), true
check 'recorded exactly once', args.state.revealed_seams, [SOCKET[:region]]
Pattern.update args
check 'still exactly once',    args.state.revealed_seams, [SOCKET[:region]]

# Noticing something is not the sort of thing that can be taken back, so the
# seam stays even when the object is dragged back out of the socket.
puts 'a revealed seam is permanent'
filler.x += (Config::SOCKET_TOLERANCE_X * 2) + 1
check 'no longer filled', Pattern.filled?(args, SOCKET), false
check 'seam stays',       Seams.revealed?(args, SOCKET[:region]), true

puts 'the tolerance box is exactly the drawn mark'
filler.x     = SOCKET[:x] + Config::SOCKET_TOLERANCE_X - 0.1
filler.depth = SOCKET[:depth]
check 'just inside on x',  Pattern.filled?(args, SOCKET), true
filler.x     = SOCKET[:x] + Config::SOCKET_TOLERANCE_X + 0.1
check 'just outside on x', Pattern.filled?(args, SOCKET), false
filler.x     = SOCKET[:x]
filler.depth = SOCKET[:depth] + Config::SOCKET_TOLERANCE_DEPTH + 0.1
check 'just outside on depth', Pattern.filled?(args, SOCKET), false

puts
puts $failures.zero? ? 'check_pattern: PASSED' : "check_pattern: #{$failures} FAILURE(S)"
exit($failures.zero? ? 0 : 1)
