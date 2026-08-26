require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'

# Minimal stand-in for DragonRuby's args.state, which is an open structure.
class FakeState
  attr_accessor :resolved_regions
end

class FakeArgs
  attr_reader :state

  def initialize
    @state = FakeState.new
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

puts 'regions do not overlap'
check 'overlapping pairs', Regions.overlapping, []

puts 'point lookup'
check 'inside fern_hollow',      Regions.at(100, 50)[:name],   :fern_hollow
check 'inside east_clearing',    Regions.at(1000, 50)[:name],  :east_clearing
check 'inside far_stand',        Regions.at(640, 250)[:name],  :far_stand
check 'corridor gap is wilds',   Regions.at(640, 50)[:name],   :wilds
check 'far corner is far_stand', Regions.at(1279, 299)[:name], :far_stand

puts 'boundaries are half-open (low edge inclusive, high edge exclusive)'
check 'x at left edge',     Regions.at(0, 50)[:name],     :fern_hollow
check 'x one before right', Regions.at(519, 50)[:name],   :fern_hollow
check 'x at right edge',    Regions.at(520, 50)[:name],   :wilds
check 'depth at low edge',  Regions.at(100, 0)[:name],    :fern_hollow
check 'depth at high edge', Regions.at(100, 160)[:name],  :far_stand

puts 'tier lookup'
args = FakeArgs.new
check 'unresolved is myth',   Regions.tier_at(args, 100, 50),  :myth
Regions.resolve! args, :fern_hollow
check 'resolved is truth',    Regions.tier_at(args, 100, 50),  :truth
check 'neighbour unaffected', Regions.tier_at(args, 1000, 50), :myth
check 'resolved? true',       Regions.resolved?(args, :fern_hollow), true
check 'resolved? false',      Regions.resolved?(args, :far_stand),   false

puts 'resolving is idempotent and refuses wilds'
Regions.resolve! args, :fern_hollow
check 'no duplicate', args.state.resolved_regions.count(:fern_hollow), 1
Regions.resolve! args, :wilds
check 'wilds never resolves', Regions.resolved?(args, :wilds), false

puts 'screen bounds'
bounds = Regions.screen_bounds({ name: :t, x: 100, depth: 0, w: 200, h: 150 })
check 'x passes through',           bounds[:x], 100
check 'w passes through',           bounds[:w], 200
check 'y is ground_y at near edge', bounds[:y], World.ground_y(0)
check 'h spans near to far',        bounds[:h], World.ground_y(150) - World.ground_y(0)

puts
puts $failures.zero? ? 'check_regions: PASSED' : "check_regions: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
